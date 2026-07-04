import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/painting.dart' show BoxFit, FilterQuality, paintImage;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'matrix_rest_service.dart';

class _MatrixNotificationAuth {
  const _MatrixNotificationAuth({
    required this.homeserver,
    required this.accessToken,
  });

  final String homeserver;
  final String accessToken;
}

class _MatrixNotificationMedia {
  const _MatrixNotificationMedia({
    this.senderAvatarUrl,
    this.roomAvatarUrl,
    this.roomName,
  });

  final String? senderAvatarUrl;
  final String? roomAvatarUrl;
  final String? roomName;
}

typedef PushMessageHandler = Future<void> Function(RemoteMessage message);
typedef PushTokenRegistrationHandler =
    Future<void> Function(String token, {String? platform});
typedef PushTokenDeletionHandler =
    Future<void> Function({String? token, String? platform});
typedef PushNotificationResponseHandler =
    Future<void> Function(NotificationResponse response);

class PushNotificationService {
  static final Object _legacyMessageHandlerOwner = Object();
  static final Map<Object, PushNotificationResponseHandler>
  _notificationResponseHandlers = <Object, PushNotificationResponseHandler>{};
  static const Set<String> _customNotificationTypes = <String>{
    'eventDatePost',
    'clubPost',
    'club',
    'event',
    'profile',
    'room',
    'eventSeriesUpdate',
    'eventRegistrationChange',
    'postComment',
    'commentReply',
  };

  PushNotificationService({
    required MatrixRestService matrixService,
    required String gatewayHost,
    required bool gatewayUseHttps,
    required String appId,
    required String appDisplayName,
    required String deviceDisplayName,
    Iterable<String> legacyAppIds = const <String>[],
  }) : _matrixService = matrixService,
       _gatewayHost = gatewayHost.trim(),
       _gatewayUseHttps = gatewayUseHttps,
       _appId = appId,
       _appDisplayName = appDisplayName,
       _deviceDisplayName = deviceDisplayName,
       _legacyAppIds = legacyAppIds
           .map((value) => value.trim())
           .where((value) => value.isNotEmpty && value != appId)
           .toSet()
           .toList(growable: false);

  static const AndroidNotificationChannel _messageChannel =
      AndroidNotificationChannel(
        'playerchat_messages',
        'Player Chat Messages',
        description: 'Notifications for incoming Matrix chat messages.',
        importance: Importance.max,
      );
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _nativeNotificationChannel = MethodChannel(
    'playerconnect/notifications',
  );
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static bool _localNotificationsInitialized = false;
  static File? _logFile;

  final MatrixRestService _matrixService;
  final String _gatewayHost;
  final bool _gatewayUseHttps;
  final String _appId;
  final String _appDisplayName;
  final String _deviceDisplayName;
  final List<String> _legacyAppIds;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  bool _initialized = false;
  bool _initialMessageHandled = false;
  String? _registeredToken;
  String? _registeredUserId;
  String? _syncInFlightKey;
  Future<void>? _syncInFlight;
  final Set<String> _legacyCleanupKeys = <String>{};
  final Map<Object, PushMessageHandler> _messageHandlers =
      <Object, PushMessageHandler>{};
  final Map<Object, PushTokenRegistrationHandler> _tokenRegistrationHandlers =
      <Object, PushTokenRegistrationHandler>{};
  final Map<Object, PushTokenDeletionHandler> _tokenDeletionHandlers =
      <Object, PushTokenDeletionHandler>{};

  bool get _isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => true,
      TargetPlatform.iOS => true,
      _ => false,
    };
  }

  Future<void> syncForCurrentSession() async {
    if (!_isSupportedPlatform) {
      _emitLog('[FCM][sync] Skipping unsupported platform.');
      return;
    }
    await _ensureInitialized();
    final matrixUserId = _matrixService.currentUserId;
    if ((matrixUserId ?? '').isEmpty) {
      _emitLog('[FCM][sync] Matrix user is empty, skipping token sync.');
      return;
    }
    final token = (await FirebaseMessaging.instance.getToken())?.trim() ?? '';
    if (token.isEmpty) {
      _emitLog('[FCM][sync] Firebase returned an empty token.');
      return;
    }
    final syncKey = _registrationKey(token, matrixUserId!);
    final cleanupKey = _legacyCleanupKey(token, matrixUserId);
    if (_registeredToken == token &&
        _registeredUserId == matrixUserId &&
        _legacyCleanupKeys.contains(cleanupKey)) {
      return;
    }
    if (_syncInFlightKey == syncKey && _syncInFlight != null) {
      await _syncInFlight;
      return;
    }
    _emitLog(
      '[FCM][sync] Token available for matrixUserId=$matrixUserId token=${_maskToken(token)} appId=$_appId',
    );
    _emitGreenDebugConsoleOnly(
      '[FCM][debug-token] matrixUserId=$matrixUserId token=$token appId=$_appId',
    );
    final operation = _registerToken(token, matrixUserId);
    _syncInFlightKey = syncKey;
    _syncInFlight = operation;
    try {
      await operation;
    } finally {
      if (_syncInFlightKey == syncKey) {
        _syncInFlightKey = null;
        _syncInFlight = null;
      }
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundMessageSubscription = null;
    _messageOpenedSubscription = null;
  }

  void bindMessageSyncHandler(
    Future<void> Function(RemoteMessage message)? handler,
  ) {
    bindMessageHandler(_legacyMessageHandlerOwner, handler);
  }

  void bindMessageHandler(Object owner, PushMessageHandler? handler) {
    if (handler == null) {
      _messageHandlers.remove(owner);
    } else {
      _messageHandlers[owner] = handler;
    }
    _emitLog(
      '[FCM][binding] Message handler ${handler == null ? 'cleared' : 'bound'} owner=${owner.runtimeType}',
    );
  }

  void bindTokenRegistrationHandler(
    Object owner,
    PushTokenRegistrationHandler? handler,
  ) {
    if (handler == null) {
      _tokenRegistrationHandlers.remove(owner);
    } else {
      _tokenRegistrationHandlers[owner] = handler;
    }
    _emitLog(
      '[FCM][binding] Token registration handler ${handler == null ? 'cleared' : 'bound'} owner=${owner.runtimeType}',
    );
  }

  void bindTokenDeletionHandler(
    Object owner,
    PushTokenDeletionHandler? handler,
  ) {
    if (handler == null) {
      _tokenDeletionHandlers.remove(owner);
    } else {
      _tokenDeletionHandlers[owner] = handler;
    }
    _emitLog(
      '[FCM][binding] Token deletion handler ${handler == null ? 'cleared' : 'bound'} owner=${owner.runtimeType}',
    );
  }

  void bindNotificationResponseHandler(
    Object owner,
    PushNotificationResponseHandler? handler,
  ) {
    if (handler == null) {
      _notificationResponseHandlers.remove(owner);
    } else {
      _notificationResponseHandlers[owner] = handler;
    }
    _emitLog(
      '[FCM][binding] Notification response handler ${handler == null ? 'cleared' : 'bound'} owner=${owner.runtimeType}',
    );
  }

  static Future<void> handleBackgroundRemoteMessage(
    RemoteMessage message,
  ) async {
    await _ensureLocalNotificationsInitialized();
    _logIncomingMessage(message, source: 'background');
    if (message.notification == null) {
      await _showLocalNotification(message, source: 'background');
    } else {
      _emitLog(
        '[FCM][background] Skipping local notification because FCM notification payload is present.',
      );
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      _emitLog('[FCM][init] Already initialized.');
      return;
    }
    _initialized = true;
    _emitLog('[FCM][init] Initializing Firebase messaging listeners.');
    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _emitLog(
      '[FCM][init] Permission status=${permission.authorizationStatus.name}',
    );
    // We show our own local/native notifications — suppress the system FCM
    // foreground display so the user doesn't see duplicates. Without this,
    // tapping the system FCM notification fires onMessageOpenedApp which has
    // no navigation handler, leaving the user on the wrong screen.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    await _ensureLocalNotificationsInitialized();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) async {
      final matrixUserId = _matrixService.currentUserId;
      if ((matrixUserId ?? '').isEmpty || token.trim().isEmpty) {
        _emitLog(
          '[FCM][token-refresh] Ignored empty token or missing Matrix user.',
        );
        return;
      }
      _emitLog(
        '[FCM][token-refresh] token=${_maskToken(token)} matrixUserId=$matrixUserId',
      );
      _emitGreenDebugConsoleOnly(
        '[FCM][debug-token-refresh] matrixUserId=$matrixUserId token=${token.trim()} appId=$_appId',
      );
      await _registerToken(token.trim(), matrixUserId!);
    });
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((
      message,
    ) {
      unawaited(
        _handleIncomingMessage(
          message,
          source: 'foreground',
          showLocalNotification: true,
        ),
      );
    });
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      unawaited(
        _handleIncomingMessage(
          message,
          source: 'opened-app',
          showLocalNotification: false,
          navigateOnOpen: true,
        ),
      );
    });
    if (!_initialMessageHandled) {
      _initialMessageHandled = true;
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _emitLog('[FCM][init] Found initial message to process.');
        await _handleIncomingMessage(
          initialMessage,
          source: 'initial-message',
          showLocalNotification: false,
          navigateOnOpen: true,
        );
      } else {
        _emitLog('[FCM][init] No initial message present.');
      }
    }
  }

  Future<void> _registerToken(String token, String matrixUserId) async {
    final gatewayUrl = _resolvedGatewayUrl;
    if (gatewayUrl == null) {
      _emitLog('[FCM][register] Gateway URL is empty, skipping registration.');
      return;
    }

    final alreadyRegistered =
        _registeredToken == token && _registeredUserId == matrixUserId;
    if (!alreadyRegistered) {
      _emitLog(
        '[FCM][register] Registering token=${_maskToken(token)} matrixUserId=$matrixUserId appId=$_appId gateway=$gatewayUrl',
      );
      if (_registeredToken != null && _registeredToken != token) {
        await _notifyTokenDeletionHandlers(token: _registeredToken);
        await _unregisterTokenAcrossKnownAppIds(_registeredToken!);
      }

      await _matrixService.registerPushToken(
        pushToken: token,
        gatewayUrl: gatewayUrl,
        appId: _appId,
        appDisplayName: _appDisplayName,
        deviceDisplayName: _deviceDisplayName,
      );
      _registeredToken = token;
      _registeredUserId = matrixUserId;
      await _notifyTokenRegistrationHandlers(token);
      _emitLog('[FCM][register] Registration completed.');
    } else {
      _emitLog(
        '[FCM][register] Token already registered for this Matrix user.',
      );
    }

    final cleanupKey = _legacyCleanupKey(token, matrixUserId);
    if (_legacyCleanupKeys.add(cleanupKey)) {
      await _cleanupLegacyPushers(token);
    }
  }

  Future<void> _handleIncomingMessage(
    RemoteMessage message, {
    required String source,
    required bool showLocalNotification,
    bool navigateOnOpen = false,
  }) async {
    _logIncomingMessage(message, source: source);
    if (navigateOnOpen) {
      // The user tapped a notification to bring the app to the foreground.
      // Synthesise a response so the navigation handlers (registered via
      // bindNotificationResponseHandler) can route to the correct room.
      final payload = _notificationPayload(message);
      final syntheticResponse = NotificationResponse(
        id: _notificationId(message),
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: payload,
      );
      _handleNotificationResponse(syntheticResponse);
    }
    if (showLocalNotification) {
      final cachedMatrixMedia = await _resolveCachedMatrixNotificationMedia(
        message,
      );
      final handledByNativeAndroid = await _showNativeAndroidMatrixNotification(
        message,
        matrixMedia: cachedMatrixMedia,
      );
      if (!handledByNativeAndroid) {
        await _showLocalNotification(
          message,
          source: source,
          matrixMedia: cachedMatrixMedia,
        );
      }
    }
    for (final handler in _messageHandlers.values) {
      await handler(message);
    }
  }

  Future<bool> _showNativeAndroidMatrixNotification(
    RemoteMessage message, {
    _MatrixNotificationMedia? matrixMedia,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    if (!_isLikelyMatrixNotification(message)) {
      return false;
    }

    final roomId = (message.data['room_id'] ?? '').toString().trim();
    final eventId = (message.data['event_id'] ?? '').toString().trim();
    if (roomId.isEmpty || eventId.isEmpty) {
      return false;
    }

    final homeserver = (message.data['homeserver'] ?? '').toString().trim();
    final accessToken = (message.data['access_token'] ?? '').toString().trim();
    final auth = (homeserver.isNotEmpty && accessToken.isNotEmpty)
        ? _MatrixNotificationAuth(
            homeserver: homeserver,
            accessToken: accessToken,
          )
        : await _loadMatrixNotificationAuth();

    final resolvedMatrixMedia =
        matrixMedia ?? await _resolveMatrixNotificationMedia(message);

    // For membership events, use the fetched room name if the payload lacks it.
    final effectiveRoomName =
        (message.data['room_name'] ?? '').toString().trim().isNotEmpty
        ? (message.data['room_name'] ?? '').toString().trim()
        : (resolvedMatrixMedia.roomName ?? '').trim();
    final membership = _membershipFromMessage(message);
    final String effectiveTitle;
    final String effectiveBody;
    if (membership == 'invite') {
      effectiveTitle = effectiveRoomName.isNotEmpty
          ? 'Invited to $effectiveRoomName'
          : 'New room invitation';
      final sender = (message.data['sender_display_name'] ?? '')
          .toString()
          .trim();
      effectiveBody = sender.isNotEmpty
          ? '$sender invited you to this room'
          : 'You have been invited to this room';
    } else if (membership == 'join') {
      effectiveTitle = effectiveRoomName.isNotEmpty
          ? 'Joined $effectiveRoomName'
          : 'You joined a room';
      effectiveBody = 'Tap to open the chat';
    } else {
      final conversationTitle = _notificationSubText(message).trim().isNotEmpty
          ? _notificationSubText(message).trim()
          : ((message.data['title'] ?? '').toString().trim().isNotEmpty
                ? (message.data['title'] ?? '').toString().trim()
                : _notificationTitle(message));
      effectiveTitle = conversationTitle;
      effectiveBody = _notificationBody(message);
    }

    try {
      await _nativeNotificationChannel.invokeMethod<void>('showNotification', {
        'roomId': roomId,
        'eventId': eventId,
        'accessToken': auth?.accessToken ?? accessToken,
        'homeserver': auth?.homeserver ?? homeserver,
        'notificationId': _notificationId(message),
        'title': effectiveTitle,
        'body': effectiveBody,
        'senderId': (message.data['sender'] ?? '').toString().trim(),
        'senderDisplayName': (message.data['sender_display_name'] ?? '')
            .toString()
            .trim(),
        'senderAvatarUrl': resolvedMatrixMedia.senderAvatarUrl,
        'roomAvatarUrl': resolvedMatrixMedia.roomAvatarUrl,
      });
      _emitLog(
        '[FCM][notification-show-native] id=${_notificationId(message)} roomId=$roomId eventId=$eventId',
      );
      return true;
    } catch (error, stackTrace) {
      _emitLog(
        '[FCM][notification-show-native-error] error=$error stackTrace=$stackTrace roomId=$roomId eventId=$eventId',
      );
      return false;
    }
  }

  Future<_MatrixNotificationMedia?> _resolveCachedMatrixNotificationMedia(
    RemoteMessage message,
  ) async {
    if (!_isLikelyMatrixNotification(message)) {
      return null;
    }

    final roomId = (message.data['room_id'] ?? '').toString().trim();
    final senderId = (message.data['sender'] ?? '').toString().trim();
    if (roomId.isEmpty) {
      return null;
    }

    final senderAvatarUrl = _matrixService.cachedParticipantAvatarUrl(
      roomId,
      senderId,
    );
    final roomAvatarUrl = _matrixService.cachedRoomAvatarUrl(roomId);
    if ((senderAvatarUrl ?? '').trim().isEmpty &&
        (roomAvatarUrl ?? '').trim().isEmpty) {
      return null;
    }

    return _MatrixNotificationMedia(
      senderAvatarUrl: senderAvatarUrl,
      roomAvatarUrl: roomAvatarUrl,
    );
  }

  Future<void> _notifyTokenRegistrationHandlers(String token) async {
    if (_tokenRegistrationHandlers.isEmpty) {
      return;
    }
    final platform = _currentPlatformName();
    for (final handler in _tokenRegistrationHandlers.values) {
      await handler(token, platform: platform);
    }
  }

  Future<void> _notifyTokenDeletionHandlers({String? token}) async {
    if (_tokenDeletionHandlers.isEmpty) {
      return;
    }
    final platform = _currentPlatformName();
    for (final handler in _tokenDeletionHandlers.values) {
      await handler(token: token, platform: platform);
    }
  }

  Future<void> _cleanupLegacyPushers(String token) async {
    for (final legacyAppId in _legacyAppIds) {
      try {
        await _matrixService.unregisterPushToken(
          pushToken: token,
          appId: legacyAppId,
        );
        _emitLog(
          '[FCM][cleanup] Removed legacy Matrix pusher appId=$legacyAppId',
        );
      } catch (error) {
        _emitLog(
          '[FCM][cleanup] Legacy Matrix pusher appId=$legacyAppId not removed: $error',
        );
      }
    }
  }

  Future<void> _unregisterTokenAcrossKnownAppIds(String token) async {
    for (final appId in <String>{_appId, ..._legacyAppIds}) {
      try {
        await _matrixService.unregisterPushToken(
          pushToken: token,
          appId: appId,
        );
      } catch (_) {
        // Keep token rollover best-effort.
      }
    }
  }

  String _legacyCleanupKey(String token, String matrixUserId) =>
      '$matrixUserId::$token';

  String _registrationKey(String token, String matrixUserId) =>
      '$_appId::$matrixUserId::$token';

  String _currentPlatformName() {
    if (kIsWeb) {
      return 'web';
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static Future<void> _ensureLocalNotificationsInitialized() async {
    if (_localNotificationsInitialized) {
      return;
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('notifications_icon'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    final androidNotifications = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidNotifications?.createNotificationChannel(_messageChannel);
    final permissionGranted = await androidNotifications
        ?.requestNotificationsPermission();
    _emitLog(
      '[FCM][local-notifications] Android notification permission=${permissionGranted?.toString() ?? 'unavailable'}',
    );
    _localNotificationsInitialized = true;
  }

  static Future<void> _showLocalNotification(
    RemoteMessage message, {
    required String source,
    _MatrixNotificationMedia? matrixMedia,
  }) async {
    final resolvedTitle = _notificationTitle(message);
    final resolvedBody = _notificationBody(message);
    final notificationPayload = _notificationPayload(message);
    final notificationId = _notificationId(message);
    // For membership events, subText shows the room name (if available).
    final subText = _notificationSubText(message);

    try {
      await _localNotificationsPlugin.show(
        id: notificationId,
        title: resolvedTitle,
        body: resolvedBody,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannel.id,
            _messageChannel.name,
            channelDescription: _messageChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            ticker: 'Player Chat message',
            icon: 'notifications_icon',
            styleInformation: BigTextStyleInformation(
              resolvedBody,
              contentTitle: resolvedTitle,
              summaryText: subText,
            ),
            subText: subText,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: notificationPayload,
      );

      if (_isLikelyMatrixNotification(message)) {
        unawaited(
          _enrichMatrixNotification(
            message: message,
            notificationId: notificationId,
            title: resolvedTitle,
            body: resolvedBody,
            payload: notificationPayload,
            matrixMedia: matrixMedia,
          ),
        );
      }

      if (_isCustomAppNotification(message)) {
        unawaited(
          _enrichCustomAppNotification(
            message: message,
            notificationId: notificationId,
            title: resolvedTitle,
            body: resolvedBody,
            payload: notificationPayload,
          ),
        );
      }

      _emitLog(
        '[FCM][notification-show] id=$notificationId payload=$notificationPayload',
      );
    } catch (error, stackTrace) {
      _emitLog(
        '[FCM][notification-show-error] error=$error stackTrace=$stackTrace payload=$notificationPayload',
      );
    }
  }

  static Future<void> _enrichCustomAppNotification({
    required RemoteMessage message,
    required int notificationId,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final avatarUrl = (message.data['senderProfilePicUrl'] ?? '')
          .toString()
          .trim();
      final imageUrl = (message.data['imageUrl'] ?? '').toString().trim();

      if (avatarUrl.isEmpty && imageUrl.isEmpty) {
        return;
      }

      final avatarFile = avatarUrl.isEmpty
          ? null
          : await _downloadNotificationImage(
              avatarUrl,
              cachePrefix: 'post_sender_avatar',
            );
      final imageFile = imageUrl.isEmpty
          ? null
          : await _downloadNotificationImage(
              imageUrl,
              cachePrefix: 'post_image',
            );

      final AndroidBitmap<Object>? largeIcon = avatarFile != null
          ? FilePathAndroidBitmap(avatarFile.path)
          : null;

      StyleInformation? styleInformation;
      if (imageFile != null) {
        styleInformation = BigPictureStyleInformation(
          FilePathAndroidBitmap(imageFile.path),
          largeIcon: largeIcon,
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: false,
        );
      } else if (largeIcon != null) {
        styleInformation = BigTextStyleInformation(body, contentTitle: title);
      }

      if (largeIcon == null && styleInformation == null) {
        return;
      }

      await _localNotificationsPlugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannel.id,
            _messageChannel.name,
            channelDescription: _messageChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            icon: 'notifications_icon',
            largeIcon: largeIcon,
            styleInformation: styleInformation,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
      _emitLog('[FCM][notification-enriched-post] id=$notificationId');
    } catch (error, stackTrace) {
      _emitLog(
        '[FCM][notification-enrich-post-error] error=$error stackTrace=$stackTrace',
      );
    }
  }

  static Future<void> _enrichMatrixNotification({
    required RemoteMessage message,
    required int notificationId,
    required String title,
    required String body,
    required String payload,
    _MatrixNotificationMedia? matrixMedia,
  }) async {
    try {
      final resolvedMatrixMedia =
          matrixMedia ?? await _resolveMatrixNotificationMedia(message);

      // For membership events, re-derive title/body now we have the room name.
      final membership = _membershipFromMessage(message);
      String effectiveTitle = title;
      String effectiveBody = body;
      if (membership == 'invite' || membership == 'join') {
        final resolvedRoomName =
            (message.data['room_name'] ?? '').toString().trim().isNotEmpty
            ? (message.data['room_name'] ?? '').toString().trim()
            : (resolvedMatrixMedia.roomName ?? '').trim();
        if (resolvedRoomName.isNotEmpty) {
          effectiveTitle = membership == 'invite'
              ? 'Invited to $resolvedRoomName'
              : 'Joined $resolvedRoomName';
        }
      }

      // For membership events use the room avatar as the large icon directly.
      final AndroidBitmap<Object>? androidLargeIcon;
      if (membership == 'invite' || membership == 'join') {
        final roomAvatarUrl = (resolvedMatrixMedia.roomAvatarUrl ?? '').trim();
        if (roomAvatarUrl.isNotEmpty) {
          final roomIconFile = await _downloadNotificationImage(
            roomAvatarUrl,
            cachePrefix: 'room_avatar_icon',
          );
          androidLargeIcon = roomIconFile != null
              ? FilePathAndroidBitmap(roomIconFile.path)
              : null;
        } else {
          androidLargeIcon = null;
        }
      } else {
        androidLargeIcon = await _resolveAndroidLargeIcon(
          message,
          fallbackSenderAvatarUrl: resolvedMatrixMedia.senderAvatarUrl,
          fallbackRoomAvatarUrl: resolvedMatrixMedia.roomAvatarUrl,
        );
      }

      final styleInformation = await _androidStyleInformation(
        message,
        title: effectiveTitle,
        body: effectiveBody,
        largeIcon: androidLargeIcon,
        roomAvatarUrl: resolvedMatrixMedia.roomAvatarUrl,
      );

      if (androidLargeIcon == null &&
          styleInformation is! BigPictureStyleInformation) {
        return;
      }

      await _localNotificationsPlugin.show(
        id: notificationId,
        title: effectiveTitle,
        body: effectiveBody,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannel.id,
            _messageChannel.name,
            channelDescription: _messageChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            ticker: 'Player Chat message',
            icon: 'notifications_icon',
            largeIcon: androidLargeIcon,
            styleInformation: styleInformation,
            subText: _notificationSubText(message),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
      _emitLog('[FCM][notification-enriched] id=$notificationId');
    } catch (error, stackTrace) {
      _emitLog(
        '[FCM][notification-enrich-error] error=$error stackTrace=$stackTrace payload=$payload',
      );
    }
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    _emitLog('[FCM][notification-tap] payload=${response.payload ?? ''}');
    for (final handler in _notificationResponseHandlers.values) {
      unawaited(handler(response));
    }
  }

  static void _logIncomingMessage(
    RemoteMessage message, {
    required String source,
  }) {
    _emitLog(
      '[FCM][$source] '
      'messageId=${message.messageId ?? ''} '
      'notificationId=${(message.data['notification_id'] ?? '').toString()} '
      'roomId=${(message.data['room_id'] ?? '').toString()} '
      'eventId=${(message.data['event_id'] ?? '').toString()} '
      'data=${jsonEncode(message.data)}',
    );
  }

  static String _notificationTitle(RemoteMessage message) {
    if (_isLikelyMatrixNotification(message)) {
      final membership = _membershipFromMessage(message);
      if (membership == 'invite') {
        final roomName = (message.data['room_name'] ?? '').toString().trim();
        return roomName.isNotEmpty
            ? 'Invited to $roomName'
            : 'New room invitation';
      }
      if (membership == 'join') {
        final roomName = (message.data['room_name'] ?? '').toString().trim();
        return roomName.isNotEmpty ? 'Joined $roomName' : 'You joined a room';
      }
      final sender = (message.data['sender_display_name'] ?? '')
          .toString()
          .trim();
      if (sender.isNotEmpty) {
        return 'New message from $sender';
      }
      return 'New message';
    }

    if (_isCustomAppNotification(message)) {
      final dataTitle = (message.data['title'] ?? '').toString().trim();
      if (dataTitle.isNotEmpty) {
        return dataTitle;
      }
    }

    final remoteTitle = message.notification?.title?.trim();
    if ((remoteTitle ?? '').isNotEmpty) {
      return remoteTitle!;
    }

    final dataTitle = (message.data['title'] ?? '').toString().trim();
    if (dataTitle.isNotEmpty) {
      return dataTitle;
    }
    return 'New message';
  }

  static String _notificationBody(RemoteMessage message) {
    final matrixMessageBody = _matrixMessageBody(message);
    if (matrixMessageBody.isNotEmpty) {
      return matrixMessageBody;
    }

    if (_isCustomAppNotification(message)) {
      final dataBody = (message.data['body'] ?? '').toString().trim();
      if (dataBody.isNotEmpty) {
        return dataBody;
      }
    }

    final remoteBody = message.notification?.body?.trim();
    if ((remoteBody ?? '').isNotEmpty) {
      return remoteBody!;
    }

    final dataBody = (message.data['body'] ?? '').toString().trim();
    if (dataBody.isNotEmpty) {
      return dataBody;
    }

    final payloadSummary = _notificationPayloadSummary(message);
    if (payloadSummary.isNotEmpty) {
      return payloadSummary;
    }
    return 'Open Player Chat to view your latest messages.';
  }

  static int _notificationId(RemoteMessage message) {
    final roomId = (message.data['room_id'] ?? '').toString();
    final rawId = message.messageId;
    final notificationId = (message.data['notification_id'] ?? '').toString();
    final eventId = (message.data['event_id'] ?? '').toString();
    final resolved = [roomId, rawId, notificationId, eventId].firstWhere(
      (value) => (value ?? '').trim().isNotEmpty,
      orElse: () => DateTime.now().microsecondsSinceEpoch.toString(),
    );
    return resolved.hashCode & 0x7fffffff;
  }

  static String _notificationPayload(RemoteMessage message) {
    final customRoutePath = _customRoutePath(message.data);
    if (customRoutePath != null && customRoutePath.isNotEmpty) {
      return jsonEncode({
        'clientName': null,
        'roomId': null,
        'eventId': null,
        'postUid': customRoutePath,
      });
    }

    final roomId = (message.data['room_id'] ?? '').toString().trim();
    final eventId = (message.data['event_id'] ?? '').toString().trim();
    return jsonEncode({
      'clientName': null,
      'roomId': roomId.isEmpty ? null : roomId,
      'eventId': eventId.isEmpty ? null : eventId,
      'postUid': null,
    });
  }

  static void _emitLog(String message) {
    debugPrint(message);
    developer.log(message, name: 'playerchat.fcm');
    unawaited(_appendAppLog(message));
  }

  static void _emitGreenDebugConsoleOnly(String message) {
    assert(() {
      const green = '\u001b[32m';
      const reset = '\u001b[0m';
      debugPrint('$green$message$reset');
      return true;
    }());
  }

  static String _maskToken(String token) {
    final trimmed = token.trim();
    if (trimmed.length <= 12) {
      return trimmed;
    }
    return '${trimmed.substring(0, 6)}...${trimmed.substring(trimmed.length - 6)}';
  }

  static String _notificationPayloadSummary(RemoteMessage message) {
    final parts = <String>[];
    final roomId = (message.data['room_id'] ?? '').toString().trim();
    final eventId = (message.data['event_id'] ?? '').toString().trim();
    final notificationId = (message.data['notification_id'] ?? '')
        .toString()
        .trim();
    if (roomId.isNotEmpty) {
      parts.add('room: $roomId');
    }
    if (eventId.isNotEmpty) {
      parts.add('event: $eventId');
    }
    if (notificationId.isNotEmpty) {
      parts.add('notification: $notificationId');
    }
    if (parts.isNotEmpty) {
      return parts.join(' | ');
    }
    if (message.data.isNotEmpty) {
      return jsonEncode(message.data);
    }
    return '';
  }

  static String? _customRoutePath(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim();
    if (!_customNotificationTypes.contains(type)) {
      return null;
    }

    final uid = _firstNonEmpty(<Object?>[
      data['uid'],
      data['eventSeriesUid'],
      data['clubUid'],
      data['postUid'],
      data['eventUid'],
      data['profileUid'],
      data['roomUid'],
    ]);
    if (uid == null) {
      return null;
    }

    switch (type) {
      case 'eventDatePost':
      case 'clubPost':
      case 'postComment':
      case 'commentReply':
        return '/post/$uid';
      case 'club':
        return '/club/$uid';
      case 'event':
        return '/events/$uid';
      case 'profile':
        return '/profile/$uid';
      case 'room':
        return '/rooms/$uid';
      case 'eventSeriesUpdate':
      case 'eventRegistrationChange':
        return '/eventSeriesSummary/$uid';
      default:
        return null;
    }
  }

  static String? _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  static Future<StyleInformation?> _androidStyleInformation(
    RemoteMessage message, {
    required String title,
    required String body,
    AndroidBitmap<Object>? largeIcon,
    String? roomAvatarUrl,
  }) async {
    if (_isCustomAppNotification(message)) {
      return null;
    }
    if (!_isLikelyMatrixNotification(message)) {
      return null;
    }
    return BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: _notificationSubText(message),
    );
  }

  static bool _isCustomAppNotification(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString().trim();
    return _customNotificationTypes.contains(type);
  }

  static bool _isLikelyMatrixNotification(RemoteMessage message) {
    final roomId = (message.data['room_id'] ?? '').toString().trim();
    final eventId = (message.data['event_id'] ?? '').toString().trim();
    final notificationId = (message.data['notification_id'] ?? '')
        .toString()
        .trim();
    return roomId.isNotEmpty || eventId.isNotEmpty || notificationId.isNotEmpty;
  }

  static Future<AndroidBitmap<Object>?> _resolveAndroidLargeIcon(
    RemoteMessage message, {
    String? fallbackSenderAvatarUrl,
    String? fallbackRoomAvatarUrl,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    final senderProfilePicUrl =
        (message.data['senderProfilePicUrl'] ?? '').toString().trim().isNotEmpty
        ? (message.data['senderProfilePicUrl'] ?? '').toString().trim()
        : (fallbackSenderAvatarUrl ?? '').trim();
    final roomAvatarUrl =
        (message.data['roomAvatarUrl'] ?? '').toString().trim().isNotEmpty
        ? (message.data['roomAvatarUrl'] ?? '').toString().trim()
        : (fallbackRoomAvatarUrl ?? '').trim();

    if (senderProfilePicUrl.isEmpty && roomAvatarUrl.isEmpty) {
      return null;
    }

    try {
      final senderIconFile = senderProfilePicUrl.isEmpty
          ? null
          : await _downloadNotificationImage(
              senderProfilePicUrl,
              cachePrefix: 'sender_profile',
            );
      final roomIconFile = roomAvatarUrl.isEmpty
          ? null
          : await _downloadNotificationImage(
              roomAvatarUrl,
              cachePrefix: 'room_avatar_icon',
            );

      final iconFile = await _composeMatrixNotificationIcon(
        senderIconFile: senderIconFile,
        roomIconFile: roomIconFile,
      );
      if (iconFile == null) {
        return null;
      }
      return FilePathAndroidBitmap(iconFile.path);
    } catch (error) {
      _emitLog(
        '[FCM][notification-icon] Failed to resolve senderProfilePicUrl=$senderProfilePicUrl roomAvatarUrl=$roomAvatarUrl error=$error',
      );
      return null;
    }
  }

  static Future<File?> _composeMatrixNotificationIcon({
    File? senderIconFile,
    File? roomIconFile,
  }) async {
    if (senderIconFile == null && roomIconFile == null) {
      return null;
    }

    if (senderIconFile != null && roomIconFile == null) {
      return senderIconFile;
    }
    if (roomIconFile != null && senderIconFile == null) {
      return roomIconFile;
    }

    final roomImage = await _decodeUiImage(await roomIconFile!.readAsBytes());
    final senderImage = await _decodeUiImage(
      await senderIconFile!.readAsBytes(),
    );
    if (roomImage == null || senderImage == null) {
      return senderIconFile;
    }

    const canvasSize = 192.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final fullRect = ui.Rect.fromLTWH(0, 0, canvasSize, canvasSize);

    canvas.drawColor(const Color(0x00000000), ui.BlendMode.clear);
    _drawCircularImage(canvas, roomImage, fullRect);

    const inset = 24.0;
    final senderRect = ui.Rect.fromLTWH(
      canvasSize / 2,
      canvasSize / 2,
      canvasSize / 2 - inset,
      canvasSize / 2 - inset,
    );

    final borderPaint = ui.Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(senderRect.center, senderRect.width / 2 + 6, borderPaint);
    _drawCircularImage(canvas, senderImage, senderRect);

    final composedImage = await recorder.endRecording().toImage(
      canvasSize.toInt(),
      canvasSize.toInt(),
    );
    final pngBytes = await composedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (pngBytes == null) {
      return senderIconFile;
    }

    final tempDirectory = await getTemporaryDirectory();
    final file = File(
      p.join(
        tempDirectory.path,
        'matrix_notification_icon_${roomIconFile.path.hashCode}_${senderIconFile.path.hashCode}.png',
      ),
    );
    await file.writeAsBytes(pngBytes.buffer.asUint8List(), flush: true);
    return file;
  }

  static Future<ui.Image?> _decodeUiImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static void _drawCircularImage(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect rect,
  ) {
    final clipPath = ui.Path()..addOval(rect);
    canvas.save();
    canvas.clipPath(clipPath);
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height),
      image: image,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    );
    canvas.restore();
  }

  static Future<File?> _downloadNotificationImage(
    String url, {
    required String cachePrefix,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }

    final response = await http.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _emitLog(
        '[FCM][notification-image] Download failed status=${response.statusCode} url=$url',
      );
      return null;
    }

    final tempDirectory = await getTemporaryDirectory();
    final extension = p.extension(uri.path).trim();
    final safeExtension = extension.isEmpty ? '.img' : extension;
    final file = File(
      p.join(
        tempDirectory.path,
        '${cachePrefix}_${uri.toString().hashCode}$safeExtension',
      ),
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  static Future<void> _appendAppLog(String message) async {
    try {
      final file = await _resolveLogFile();
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString(
        '[$timestamp] $message\n\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Keep push flow intact if file logging is unavailable.
    }
  }

  static Future<File> _resolveLogFile() async {
    final existing = _logFile;
    if (existing != null) {
      return existing;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final file = File(p.join(supportDirectory.path, 'app.log'));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _logFile = file;
    return file;
  }

  static String _notificationSubText(RemoteMessage message) {
    if (!_isLikelyMatrixNotification(message)) {
      return '';
    }

    final room = (message.data['room_name'] ?? '').toString().trim();
    return room;
  }

  static String _matrixMessageBody(RemoteMessage message) {
    if (!_isLikelyMatrixNotification(message)) {
      return '';
    }

    // Friendly body for membership events.
    final membership = _membershipFromMessage(message);
    if (membership == 'invite') {
      final sender = (message.data['sender_display_name'] ?? '')
          .toString()
          .trim();
      return sender.isNotEmpty
          ? '$sender invited you to this room'
          : 'You have been invited to this room';
    }
    if (membership == 'join') {
      return 'Tap to open the chat';
    }

    final dataBody = (message.data['body'] ?? '').toString().trim();
    if (dataBody.isNotEmpty && dataBody != 'New event') {
      return dataBody;
    }

    final rawContent = message.data['content'];
    Map<String, dynamic>? content;
    if (rawContent is Map) {
      content = rawContent.cast<String, dynamic>();
    } else if (rawContent is String && rawContent.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawContent);
        if (decoded is Map<String, dynamic>) {
          content = decoded;
        }
      } catch (_) {
        // Ignore malformed content payloads and use generic fallbacks.
      }
    }

    final contentBody = (content?['body'] ?? '').toString().trim();
    if (contentBody.isNotEmpty) {
      return contentBody;
    }

    final msgType = (content?['msgtype'] ?? '').toString().trim();
    switch (msgType) {
      case 'm.image':
        return 'Image';
      case 'm.video':
        return 'Video';
      case 'm.audio':
        return 'Audio';
      case 'm.file':
        return 'File';
      default:
        return '';
    }
  }

  static Future<_MatrixNotificationMedia> _resolveMatrixNotificationMedia(
    RemoteMessage message,
  ) async {
    if (!_isLikelyMatrixNotification(message)) {
      return const _MatrixNotificationMedia();
    }

    final senderAvatarUrl = (message.data['senderProfilePicUrl'] ?? '')
        .toString()
        .trim();
    final roomAvatarUrl = (message.data['roomAvatarUrl'] ?? '')
        .toString()
        .trim();
    if (senderAvatarUrl.isNotEmpty || roomAvatarUrl.isNotEmpty) {
      return _MatrixNotificationMedia(
        senderAvatarUrl: senderAvatarUrl.isEmpty ? null : senderAvatarUrl,
        roomAvatarUrl: roomAvatarUrl.isEmpty ? null : roomAvatarUrl,
      );
    }

    final roomId = (message.data['room_id'] ?? '').toString().trim();
    final senderId = (message.data['sender'] ?? '').toString().trim();
    if (roomId.isEmpty) {
      return const _MatrixNotificationMedia();
    }

    final auth = await _loadMatrixNotificationAuth();
    if (auth == null) {
      return const _MatrixNotificationMedia();
    }

    String? resolvedSenderAvatarUrl;
    String? resolvedRoomAvatarUrl;
    String? resolvedRoomName;

    final membership = _membershipFromMessage(message);
    final isMembershipEvent = membership == 'invite' || membership == 'join';

    // For regular messages fetch the sender's avatar.
    if (senderId.isNotEmpty && !isMembershipEvent) {
      final memberJson = await _matrixGetJson(
        auth,
        '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.member/${Uri.encodeComponent(senderId)}',
      );
      resolvedSenderAvatarUrl = _mxcToThumbnailUrl(
        auth.homeserver,
        (memberJson?['avatar_url'] ?? '').toString(),
      );
    }

    // Fetch room avatar.
    final roomAvatarJson = await _matrixGetJson(
      auth,
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.avatar',
    );
    resolvedRoomAvatarUrl = _mxcToThumbnailUrl(
      auth.homeserver,
      (roomAvatarJson?['url'] ?? '').toString(),
    );

    // For membership events also fetch the room name if not already in payload.
    if (isMembershipEvent &&
        (message.data['room_name'] ?? '').toString().trim().isEmpty) {
      final roomNameJson = await _matrixGetJson(
        auth,
        '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.name',
      );
      resolvedRoomName = (roomNameJson?['name'] ?? '').toString().trim();
    }

    return _MatrixNotificationMedia(
      senderAvatarUrl: resolvedSenderAvatarUrl,
      roomAvatarUrl: resolvedRoomAvatarUrl,
      roomName: resolvedRoomName,
    );
  }

  /// Returns the `membership` string from the message content if this is a
  /// Matrix m.room.member event, otherwise null.
  static String? _membershipFromMessage(RemoteMessage message) {
    final rawContent = message.data['content'];
    Map<String, dynamic>? content;
    if (rawContent is Map) {
      content = rawContent.cast<String, dynamic>();
    } else if (rawContent is String && rawContent.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawContent);
        if (decoded is Map<String, dynamic>) content = decoded;
      } catch (_) {}
    }
    if (content == null) return null;
    final membership = (content['membership'] ?? '').toString().trim();
    return membership.isEmpty ? null : membership;
  }

  static Future<_MatrixNotificationAuth?> _loadMatrixNotificationAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final homeserver = (prefs.getString('homeserver_url') ?? '').trim();
      final accessToken = (prefs.getString('access_token') ?? '').trim();
      if (homeserver.isNotEmpty && accessToken.isNotEmpty) {
        return _MatrixNotificationAuth(
          homeserver: homeserver,
          accessToken: accessToken,
        );
      }
    } catch (_) {
      // Fall back to secure storage backup.
    }

    try {
      final all = await _secureStorage.readAll();
      for (final value in all.values) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is! Map) {
            continue;
          }
          final homeserver = (decoded['homeserver'] ?? '').toString().trim();
          final accessToken = (decoded['accessToken'] ?? '').toString().trim();
          if (homeserver.isNotEmpty && accessToken.isNotEmpty) {
            return _MatrixNotificationAuth(
              homeserver: homeserver,
              accessToken: accessToken,
            );
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // No persisted Matrix auth available for avatar lookup.
    }

    return null;
  }

  static Future<Map<String, dynamic>?> _matrixGetJson(
    _MatrixNotificationAuth auth,
    String path,
  ) async {
    try {
      final base = auth.homeserver.endsWith('/')
          ? auth.homeserver.substring(0, auth.homeserver.length - 1)
          : auth.homeserver;
      final response = await http.get(
        Uri.parse('$base$path'),
        headers: <String, String>{
          'Authorization': 'Bearer ${auth.accessToken}',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _mxcToThumbnailUrl(String homeserver, String mxcUrl) {
    final trimmedHomeserver = homeserver.trim();
    final trimmedMxc = mxcUrl.trim();
    if (trimmedHomeserver.isEmpty || !trimmedMxc.startsWith('mxc://')) {
      return null;
    }

    final uri = Uri.tryParse(trimmedMxc);
    final serverName = uri?.host ?? '';
    final mediaId = uri?.pathSegments.join('/') ?? '';
    if (serverName.isEmpty || mediaId.isEmpty) {
      return null;
    }

    final base = trimmedHomeserver.endsWith('/')
        ? trimmedHomeserver.substring(0, trimmedHomeserver.length - 1)
        : trimmedHomeserver;
    return '$base/_matrix/media/v3/thumbnail/$serverName/$mediaId?width=128&height=128&method=crop';
  }

  String? get _resolvedGatewayUrl {
    if (_gatewayHost.isEmpty) {
      return null;
    }
    final withScheme = _gatewayHost.contains('://')
        ? _gatewayHost
        : '${_gatewayUseHttps ? 'https' : 'http'}://$_gatewayHost';
    final uri = Uri.parse(withScheme);
    final trimmedPath = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final nextPath = trimmedPath.endsWith('/_matrix/push/v1/notify')
        ? trimmedPath
        : '${trimmedPath.isEmpty ? '' : trimmedPath}/_matrix/push/v1/notify';
    return uri.replace(path: nextPath).toString();
  }
}
