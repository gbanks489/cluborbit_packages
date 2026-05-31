import 'package:flutter/services.dart';

import 'matrix_low_level_client.dart';
import 'matrix_transport_client.dart';

class MatrixRustCryptoTransportClient implements MatrixTransportClient {
  MatrixRustCryptoTransportClient({
    required String homeserver,
    required String clientName,
    MethodChannel? channel,
    MatrixLowLevelClient? fallbackTransport,
  }) : _homeserver = homeserver,
       _clientName = clientName,
       _channel = channel ?? const MethodChannel(_channelName),
       _fallback =
           fallbackTransport ?? MatrixLowLevelClient(homeserver: homeserver);

  static const String _channelName = 'playerchat_matrix/matrix_rust_crypto';

  final String _homeserver;
  final String _clientName;
  final MethodChannel _channel;
  final MatrixLowLevelClient _fallback;

  bool? _nativeAvailable;
  bool _usingNativeSession = false;
  String? _currentUserId;
  String? _accessToken;
  String? _sinceToken;

  @override
  MatrixTransportCapabilities get capabilities {
    if (_usingNativeSession && _nativeAvailable == true) {
      return const MatrixTransportCapabilities(
        transportId: 'matrix-rust-crypto-native',
        supportsRoomEncryptionState: true,
        supportsDeviceKeys: true,
        supportsMegolmEncryption: true,
        supportsMegolmDecryption: true,
      );
    }
    return _fallback.capabilities;
  }

  @override
  String? get currentUserId => _currentUserId ?? _fallback.currentUserId;

  @override
  bool get isLoggedIn {
    if (_usingNativeSession) {
      return (currentUserId ?? '').isNotEmpty &&
          (_accessToken ?? '').isNotEmpty;
    }
    return _fallback.isLoggedIn;
  }

  @override
  String? get sinceToken => _sinceToken ?? _fallback.sinceToken;

  @override
  void restoreSinceToken(String? token) {
    final normalized = _normalize(token);
    _sinceToken = normalized;
    _fallback.restoreSinceToken(normalized);
  }

  @override
  Future<MatrixLowLevelLoginResult> loginPassword({
    required String username,
    required String password,
    String initialDeviceDisplayName = 'PlayerChat REST Client',
  }) async {
    final nativeResponse = await _invokeMap('loginPassword', <String, dynamic>{
      ..._baseArgs,
      'username': username,
      'password': password,
      'initialDeviceDisplayName': initialDeviceDisplayName,
    });
    if (nativeResponse != null) {
      final result = MatrixLowLevelLoginResult(
        userId: (nativeResponse['userId'] ?? '').toString(),
        accessToken: (nativeResponse['accessToken'] ?? '').toString(),
        deviceId: _normalize(nativeResponse['deviceId']?.toString()),
      );
      _usingNativeSession = true;
      _currentUserId = result.userId;
      _accessToken = result.accessToken;
      _fallback.restoreSession(
        accessToken: result.accessToken,
        userId: result.userId,
        deviceId: result.deviceId,
        sinceToken: sinceToken,
      );
      return result;
    }

    _usingNativeSession = false;
    final result = await _fallback.loginPassword(
      username: username,
      password: password,
      initialDeviceDisplayName: initialDeviceDisplayName,
    );
    _currentUserId = result.userId;
    _accessToken = result.accessToken;
    return result;
  }

  @override
  Future<void> logout() async {
    if (_usingNativeSession) {
      await _invokeVoid('logout', <String, dynamic>{..._baseArgs});
      _fallback.clearSession();
    } else {
      await _fallback.logout();
    }
    _usingNativeSession = false;
    _currentUserId = null;
    _accessToken = null;
    _sinceToken = null;
  }

  @override
  Future<Map<String, dynamic>> sync({
    int timeoutMs = 0,
    bool fullState = false,
  }) async {
    if (_usingNativeSession) {
      final nativeResponse = await _invokeMap('sync', <String, dynamic>{
        ..._baseArgs,
        'timeoutMs': timeoutMs,
        'fullState': fullState,
        'sinceToken': sinceToken,
      });
      if (nativeResponse != null) {
        restoreSinceToken(nativeResponse['next_batch']?.toString());
        return nativeResponse;
      }
    }
    return _fallback.sync(timeoutMs: timeoutMs, fullState: fullState);
  }

  @override
  Future<Map<String, dynamic>> getRoomMessagesRaw(
    String roomId, {
    int limit = 60,
  }) async {
    if (_usingNativeSession) {
      final nativeResponse = await _invokeMap(
        'getRoomMessagesRaw',
        <String, dynamic>{..._baseArgs, 'roomId': roomId, 'limit': limit},
      );
      if (nativeResponse != null) {
        return nativeResponse;
      }
    }
    return _fallback.getRoomMessagesRaw(roomId, limit: limit);
  }

  @override
  Future<Map<String, dynamic>> getEvent(String roomId, String eventId) async {
    if (_usingNativeSession) {
      final nativeResponse = await _invokeMap('getEvent', <String, dynamic>{
        ..._baseArgs,
        'roomId': roomId,
        'eventId': eventId,
      });
      if (nativeResponse != null) {
        return nativeResponse;
      }
    }
    return _fallback.getEvent(roomId, eventId);
  }

  @override
  Future<Map<String, dynamic>> getPresenceStatus(String userId) {
    return _fallback.getPresenceStatus(userId);
  }

  @override
  Future<Map<String, dynamic>> getState(String roomId) async {
    if (_usingNativeSession) {
      final nativeResponse = await _invokeMap('getState', <String, dynamic>{
        ..._baseArgs,
        'roomId': roomId,
      });
      if (nativeResponse != null) {
        return nativeResponse;
      }
    }
    return _fallback.getState(roomId);
  }

  @override
  Future<List<dynamic>> getStateEvents(String roomId) async {
    if (_usingNativeSession) {
      final nativeResponse = await _invokeList(
        'getStateEvents',
        <String, dynamic>{..._baseArgs, 'roomId': roomId},
      );
      if (nativeResponse != null) {
        return nativeResponse;
      }
    }
    return _fallback.getStateEvents(roomId);
  }

  @override
  Future<Map<String, dynamic>> getMembers(String roomId) {
    return _fallback.getMembers(roomId);
  }

  @override
  Future<void> joinRoom(String roomId) {
    return _fallback.joinRoom(roomId);
  }

  @override
  Future<void> leaveRoom(String roomId) {
    return _fallback.leaveRoom(roomId);
  }

  @override
  Future<void> setRoomAvatar(String roomId, String mxcUrl) {
    return _fallback.setRoomAvatar(roomId, mxcUrl);
  }

  @override
  Future<void> setHttpPusher({
    required String pushKey,
    required String appId,
    required String appDisplayName,
    required String deviceDisplayName,
    required String url,
    String lang = 'en',
    String profileTag = 'mobile',
    String format = 'event_id_only',
  }) {
    return _fallback.setHttpPusher(
      pushKey: pushKey,
      appId: appId,
      appDisplayName: appDisplayName,
      deviceDisplayName: deviceDisplayName,
      url: url,
      lang: lang,
      profileTag: profileTag,
      format: format,
    );
  }

  @override
  Future<void> deletePusher({required String pushKey, required String appId}) {
    return _fallback.deletePusher(pushKey: pushKey, appId: appId);
  }

  @override
  Future<String> sendText(
    String roomId,
    String body, {
    String? replyToEventId,
  }) async {
    if (_usingNativeSession) {
      final nativeResponse = await _invokeMap('sendText', <String, dynamic>{
        ..._baseArgs,
        'roomId': roomId,
        'body': body,
        'replyToEventId': replyToEventId,
      });
      final eventId = _normalize(nativeResponse?['eventId']?.toString());
      if (eventId != null) {
        return eventId;
      }
    }
    return _fallback.sendText(roomId, body, replyToEventId: replyToEventId);
  }

  @override
  Future<String> editText(String roomId, String eventId, String newBody) async {
    if (_usingNativeSession) {
      final nativeResponse = await _invokeMap('editText', <String, dynamic>{
        ..._baseArgs,
        'roomId': roomId,
        'eventId': eventId,
        'newBody': newBody,
      });
      final newEventId = _normalize(nativeResponse?['eventId']?.toString());
      if (newEventId != null) {
        return newEventId;
      }
    }
    return _fallback.editText(roomId, eventId, newBody);
  }

  @override
  Future<String> uploadMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) {
    return _fallback.uploadMedia(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
  }

  @override
  Future<String> sendMediaMessage({
    required String roomId,
    required String msgtype,
    required String body,
    required String mxcUrl,
    required String mimeType,
    String? caption,
    bool isForwarded = false,
  }) {
    return _fallback.sendMediaMessage(
      roomId: roomId,
      msgtype: msgtype,
      body: body,
      mxcUrl: mxcUrl,
      mimeType: mimeType,
      caption: caption,
      isForwarded: isForwarded,
    );
  }

  @override
  Future<void> sendReaction({
    required String roomId,
    required String eventId,
    required String emoji,
  }) {
    return _fallback.sendReaction(
      roomId: roomId,
      eventId: eventId,
      emoji: emoji,
    );
  }

  @override
  Future<void> redact({
    required String roomId,
    required String eventId,
    String? reason,
  }) {
    return _fallback.redact(roomId: roomId, eventId: eventId, reason: reason);
  }

  @override
  Future<void> setTyping({
    required String roomId,
    required bool isTyping,
    int timeoutMs = 15000,
  }) {
    return _fallback.setTyping(
      roomId: roomId,
      isTyping: isTyping,
      timeoutMs: timeoutMs,
    );
  }

  @override
  Future<void> setReadMarker({
    required String roomId,
    required String eventId,
  }) {
    return _fallback.setReadMarker(roomId: roomId, eventId: eventId);
  }

  @override
  Future<MatrixTurnServerConfig> getTurnServerConfig() {
    return _fallback.getTurnServerConfig();
  }

  @override
  Future<String> sendCallEvent({
    required String roomId,
    required String eventType,
    required Map<String, dynamic> content,
  }) {
    return _fallback.sendCallEvent(
      roomId: roomId,
      eventType: eventType,
      content: content,
    );
  }

  @override
  Future<String> createRoom({
    required String name,
    required List<String> invite,
    required bool isDirect,
    List<Map<String, dynamic>> initialState = const <Map<String, dynamic>>[],
  }) async {
    if (_usingNativeSession) {
      final nativeArgs = <String, dynamic>{
        ..._baseArgs,
        'invite': invite,
        'isDirect': isDirect,
        'initialState': initialState,
      };
      if (name.trim().isNotEmpty) {
        nativeArgs['name'] = name;
      }
      final nativeResponse = await _invokeMap('createRoom', nativeArgs);
      final roomId = _normalize(nativeResponse?['roomId']?.toString());
      if (roomId != null) {
        return roomId;
      }
    }
    return _fallback.createRoom(
      name: name,
      invite: invite,
      isDirect: isDirect,
      initialState: initialState,
    );
  }

  @override
  String mxcToThumbnailHttp(Uri? uri) => _fallback.mxcToThumbnailHttp(uri);

  @override
  String mxcToDownloadHttp(Uri? uri) => _fallback.mxcToDownloadHttp(uri);

  @override
  Future<List<int>> downloadMedia(String downloadUrl) {
    return _fallback.downloadMedia(downloadUrl);
  }

  @override
  Future<String> startVerification({required String userId}) {
    return _fallback.startVerification(userId: userId);
  }

  @override
  Future<void> acceptVerification(String verificationId) {
    return _fallback.acceptVerification(verificationId);
  }

  @override
  Future<void> rejectVerification(String verificationId) {
    return _fallback.rejectVerification(verificationId);
  }

  @override
  Future<void> acceptSas(String verificationId) {
    return _fallback.acceptSas(verificationId);
  }

  @override
  Future<void> rejectSas(String verificationId) {
    return _fallback.rejectSas(verificationId);
  }

  @override
  List<Map<String, dynamic>> getVerificationSessions() {
    return _fallback.getVerificationSessions();
  }

  @override
  void dispose() {
    _fallback.dispose();
  }

  Map<String, dynamic> get _baseArgs => <String, dynamic>{
    'homeserver': _homeserver,
    'clientName': _clientName,
  };

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<bool> _ensureNativeAvailable() async {
    final cached = _nativeAvailable;
    if (cached != null) {
      return cached;
    }
    try {
      final available = await _channel.invokeMethod<bool>(
        'isAvailable',
        _baseArgs,
      );
      _nativeAvailable = available ?? false;
    } on MissingPluginException {
      _nativeAvailable = false;
    } on PlatformException catch (error) {
      if (_isMissingImplementation(error)) {
        _nativeAvailable = false;
      } else {
        rethrow;
      }
    }
    return _nativeAvailable ?? false;
  }

  bool _isMissingImplementation(PlatformException error) {
    final code = error.code.toLowerCase();
    return code == 'unimplemented' ||
        code == 'not_implemented' ||
        code == 'missing_plugin';
  }

  Future<Map<String, dynamic>?> _invokeMap(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    if (!await _ensureNativeAvailable()) {
      return null;
    }
    try {
      final result = await _channel.invokeMapMethod<dynamic, dynamic>(
        method,
        arguments,
      );
      if (result == null) {
        return null;
      }
      return result.map((key, value) => MapEntry(key.toString(), value));
    } on MissingPluginException {
      _nativeAvailable = false;
      return null;
    } on PlatformException catch (error) {
      if (_isMissingImplementation(error)) {
        _nativeAvailable = false;
        return null;
      }
      rethrow;
    }
  }

  Future<List<dynamic>?> _invokeList(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    if (!await _ensureNativeAvailable()) {
      return null;
    }
    try {
      return await _channel.invokeListMethod<dynamic>(method, arguments);
    } on MissingPluginException {
      _nativeAvailable = false;
      return null;
    } on PlatformException catch (error) {
      if (_isMissingImplementation(error)) {
        _nativeAvailable = false;
        return null;
      }
      rethrow;
    }
  }

  Future<void> _invokeVoid(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    if (!await _ensureNativeAvailable()) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      _nativeAvailable = false;
    } on PlatformException catch (error) {
      if (_isMissingImplementation(error)) {
        _nativeAvailable = false;
        return;
      }
      rethrow;
    }
  }
}
