import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'matrix_rest_service.dart';

class PushNotificationService {
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
  Future<void> Function(RemoteMessage message)? _messageSyncHandler;

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
    _messageSyncHandler = handler;
    _emitLog(
      '[FCM][binding] Message sync handler ${handler == null ? 'cleared' : 'bound'}.',
    );
  }

  static Future<void> handleBackgroundRemoteMessage(
    RemoteMessage message,
  ) async {
    await _ensureLocalNotificationsInitialized();
    _logIncomingMessage(message, source: 'background');
    await _showLocalNotification(message, source: 'background');
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
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
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
  }) async {
    _logIncomingMessage(message, source: source);
    if (showLocalNotification) {
      await _showLocalNotification(message, source: source);
    }
    await _messageSyncHandler?.call(message);
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

  static Future<void> _ensureLocalNotificationsInitialized() async {
    if (_localNotificationsInitialized) {
      return;
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
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
  }) async {
    final payload = jsonEncode(<String, Object?>{
      'source': source,
      'messageId': message.messageId,
      'data': message.data,
    });

    try {
      await _localNotificationsPlugin.show(
        id: _notificationId(message),
        title: _notificationTitle(message),
        body: _notificationBody(message),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannel.id,
            _messageChannel.name,
            channelDescription: _messageChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            ticker: 'Player Chat message',
            icon: 'ic_notification',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
      _emitLog(
        '[FCM][notification-show] id=${_notificationId(message)} payload=$payload',
      );
    } catch (error, stackTrace) {
      _emitLog(
        '[FCM][notification-show-error] error=$error stackTrace=$stackTrace payload=$payload',
      );
    }
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    _emitLog('[FCM][notification-tap] payload=${response.payload ?? ''}');
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
    final remoteTitle = message.notification?.title?.trim();
    if ((remoteTitle ?? '').isNotEmpty) {
      return remoteTitle!;
    }
    return 'New message';
  }

  static String _notificationBody(RemoteMessage message) {
    final remoteBody = message.notification?.body?.trim();
    if ((remoteBody ?? '').isNotEmpty) {
      return remoteBody!;
    }

    final payloadSummary = _notificationPayloadSummary(message);
    if (payloadSummary.isNotEmpty) {
      return payloadSummary;
    }
    return 'Open Player Chat to view your latest messages.';
  }

  static int _notificationId(RemoteMessage message) {
    final rawId = message.messageId;
    final notificationId = (message.data['notification_id'] ?? '').toString();
    final eventId = (message.data['event_id'] ?? '').toString();
    final resolved = [rawId, notificationId, eventId].firstWhere(
      (value) => (value ?? '').trim().isNotEmpty,
      orElse: () => DateTime.now().microsecondsSinceEpoch.toString(),
    );
    return resolved.hashCode & 0x7fffffff;
  }

  static void _emitLog(String message) {
    debugPrint(message);
    developer.log(message, name: 'playerchat.fcm');
    unawaited(_appendAppLog(message));
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
