// ignore_for_file: annotate_overrides

import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';

import 'package:http/http.dart' as http;

import 'matrix_transport_client.dart';

class MatrixLowLevelClient implements MatrixTransportClient {
  MatrixLowLevelClient({required String homeserver, http.Client? httpClient})
    : _homeserver = homeserver.endsWith('/')
          ? homeserver.substring(0, homeserver.length - 1)
          : homeserver,
      _http = httpClient ?? http.Client();

  final String _homeserver;
  final http.Client _http;
  bool _disposed = false;

  String? _accessToken;
  String? _userId;
  String? _deviceId;
  String? _since;

  String? get sinceToken => _since;

  void restoreSession({
    required String accessToken,
    required String userId,
    String? deviceId,
    String? sinceToken,
  }) {
    _accessToken = accessToken;
    _userId = userId;
    _deviceId = deviceId;
    restoreSinceToken(sinceToken);
  }

  void clearSession() {
    _accessToken = null;
    _userId = null;
    _deviceId = null;
    _since = null;
  }

  void restoreSinceToken(String? token) {
    final normalized = (token ?? '').trim();
    _since = normalized.isEmpty ? null : normalized;
  }

  // Verification session tracking.
  final Map<String, Map<String, dynamic>> _verificationSessions =
      <String, Map<String, dynamic>>{};

  @override
  String? get currentUserId => _userId;
  @override
  bool get isLoggedIn => (_accessToken ?? '').isNotEmpty;
  @override
  MatrixTransportCapabilities get capabilities =>
      const MatrixTransportCapabilities(
        transportId: 'sdk-free-rest',
        supportsRoomEncryptionState: true,
        supportsDeviceKeys: false,
        supportsMegolmEncryption: false,
        supportsMegolmDecryption: false,
      );

  Uri _clientUri(String path, [Map<String, String>? query]) {
    return Uri.parse(
      '$_homeserver/_matrix/client/v3$path',
    ).replace(queryParameters: query);
  }

  Uri _mediaUri(String path, [Map<String, String>? query]) {
    return Uri.parse(
      '$_homeserver/_matrix/media/v3$path',
    ).replace(queryParameters: query);
  }

  String _txnId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '${now}_$rand';
  }

  Map<String, String> _authHeaders({
    Map<String, String>? extra,
    bool json = true,
  }) {
    final headers = <String, String>{};
    if (json) {
      headers['content-type'] = 'application/json';
    }
    final token = _accessToken;
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    final body = response.body.isEmpty ? '{}' : response.body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{'error': 'Non-JSON response', 'raw': body};
    }
  }

  Future<Object?> _decodeAny(http.Response response) async {
    final body = response.body.isEmpty ? 'null' : response.body;
    try {
      return jsonDecode(body);
    } on FormatException {
      return <String, dynamic>{'error': 'Non-JSON response', 'raw': body};
    }
  }

  String _responseSnippet(String body, {int max = 180}) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= max) {
      return compact;
    }
    return '${compact.substring(0, max)}...';
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    Object? body,
  }) async {
    if (_disposed) {
      throw StateError('Matrix HTTP client is disposed');
    }
    late final http.Response response;
    switch (method) {
      case 'GET':
        response = await _http.get(uri, headers: headers);
      case 'POST':
        response = await _http.post(uri, headers: headers, body: body);
      case 'PUT':
        response = await _http.put(uri, headers: headers, body: body);
      default:
        throw UnsupportedError('Unsupported HTTP method $method');
    }

    final jsonMap = await _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errcode = (jsonMap['errcode'] ?? '').toString().trim();
      final message = jsonMap['error'] ?? 'HTTP ${response.statusCode}';
      final prefix = errcode.isEmpty
          ? 'Matrix HTTP error'
          : 'Matrix HTTP error [$errcode]';
      throw StateError('$prefix: $message');
    }
    return jsonMap;
  }

  Future<MatrixLowLevelLoginResult> loginPassword({
    required String username,
    required String password,
    String initialDeviceDisplayName = 'PlayerChat REST Client',
  }) async {
    final uri = _clientUri('/login');
    final res = await _requestJson(
      method: 'POST',
      uri: uri,
      headers: _authHeaders(),
      body: jsonEncode({
        'type': 'm.login.password',
        'identifier': {'type': 'm.id.user', 'user': username},
        'password': password,
        'initial_device_display_name': initialDeviceDisplayName,
      }),
    );

    _accessToken = (res['access_token'] ?? '').toString();
    _userId = (res['user_id'] ?? username).toString();
    _deviceId = (res['device_id'] ?? '').toString();

    return MatrixLowLevelLoginResult(
      userId: _userId ?? username,
      accessToken: _accessToken ?? '',
      deviceId: _deviceId,
    );
  }

  Future<void> logout() async {
    if (!isLoggedIn) return;
    final uri = _clientUri('/logout');
    await _requestJson(method: 'POST', uri: uri, headers: _authHeaders());
    _accessToken = null;
    _userId = null;
    _deviceId = null;
    _since = null;
  }

  Future<Map<String, dynamic>> sync({
    int timeoutMs = 0,
    bool fullState = false,
  }) async {
    final useSince = !fullState && (_since ?? '').isNotEmpty;
    Future<Map<String, dynamic>> runSync({required bool includeSince}) {
      final query = <String, String>{'timeout': '$timeoutMs'};
      if (includeSince && (_since ?? '').isNotEmpty) {
        query['since'] = _since!;
      }
      if (fullState) query['full_state'] = 'true';
      query['filter'] = jsonEncode({
        'room': {
          'timeline': {'limit': 20},
        },
      });
      return _requestJson(
        method: 'GET',
        uri: _clientUri('/sync', query),
        headers: _authHeaders(json: false),
      );
    }

    late final Map<String, dynamic> res;
    try {
      res = await runSync(includeSince: useSince);
    } on StateError catch (error) {
      final message = error.toString().toLowerCase();
      final looksLikeInvalidSince =
          message.contains('m_unknown_pos') ||
          message.contains('unknown pos') ||
          message.contains('unknown position') ||
          message.contains('since');
      if (!useSince || !looksLikeInvalidSince) {
        rethrow;
      }
      _since = null;
      res = await runSync(includeSince: false);
    }

    final nextBatch = res['next_batch'];
    if (nextBatch is String && nextBatch.isNotEmpty) {
      _since = nextBatch;
    }
    return res;
  }

  Future<Map<String, dynamic>> getRoomMessagesRaw(
    String roomId, {
    int limit = 60,
  }) async {
    final res = await _requestJson(
      method: 'GET',
      uri: _clientUri('/rooms/$roomId/messages', {
        'dir': 'b',
        'limit': '$limit',
      }),
      headers: _authHeaders(json: false),
    );
    return res;
  }

  Future<Map<String, dynamic>> getEvent(String roomId, String eventId) {
    return _requestJson(
      method: 'GET',
      uri: _clientUri('/rooms/$roomId/event/$eventId'),
      headers: _authHeaders(json: false),
    );
  }

  Future<Map<String, dynamic>> getPresenceStatus(String userId) {
    final encodedUserId = Uri.encodeComponent(userId);
    return _requestJson(
      method: 'GET',
      uri: _clientUri('/presence/$encodedUserId/status'),
      headers: _authHeaders(json: false),
    );
  }

  Future<Map<String, dynamic>> getState(String roomId) {
    return _requestJson(
      method: 'GET',
      uri: _clientUri('/rooms/$roomId/state'),
      headers: _authHeaders(json: false),
    );
  }

  Future<List<dynamic>> getStateEvents(String roomId) async {
    if (_disposed) {
      throw StateError('Matrix HTTP client is disposed');
    }
    final response = await _http.get(
      _clientUri('/rooms/$roomId/state'),
      headers: _authHeaders(json: false),
    );
    final decoded = await _decodeAny(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final map = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'error': 'HTTP ${response.statusCode}'};
      final errcode = (map['errcode'] ?? '').toString().trim();
      final message = map['error'] ?? 'HTTP ${response.statusCode}';
      final prefix = errcode.isEmpty
          ? 'Matrix HTTP error'
          : 'Matrix HTTP error [$errcode]';
      throw StateError('$prefix: $message');
    }
    if (decoded is List<dynamic>) {
      return decoded;
    }
    return const <dynamic>[];
  }

  Future<String> resolveRoomAlias(String roomAlias) async {
    final alias = roomAlias.trim();
    if (alias.isEmpty || alias.startsWith('!')) {
      return alias;
    }

    final encodedAlias = Uri.encodeComponent(alias);
    final res = await _requestJson(
      method: 'GET',
      uri: _clientUri('/directory/room/$encodedAlias'),
      headers: _authHeaders(json: false),
    );
    final roomId = (res['room_id'] ?? '').toString().trim();
    if (roomId.isEmpty) {
      throw StateError('Matrix alias resolution failed for $alias');
    }
    return roomId;
  }

  Future<Map<String, dynamic>> getMembers(String roomId) {
    return _requestJson(
      method: 'GET',
      uri: _clientUri('/rooms/$roomId/members'),
      headers: _authHeaders(json: false),
    );
  }

  Future<void> joinRoom(String roomId) async {
    await _requestJson(
      method: 'POST',
      uri: _clientUri('/rooms/$roomId/join'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{}),
    );
  }

  Future<void> leaveRoom(String roomId) async {
    await _requestJson(
      method: 'POST',
      uri: _clientUri('/rooms/$roomId/leave'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{}),
    );
  }

  Future<void> setRoomAvatar(String roomId, String mxcUrl) async {
    await _requestJson(
      method: 'PUT',
      uri: _clientUri('/rooms/$roomId/state/m.room.avatar'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{'url': mxcUrl}),
    );
  }

  Future<void> setHttpPusher({
    required String pushKey,
    required String appId,
    required String appDisplayName,
    required String deviceDisplayName,
    required String url,
    String lang = 'en',
    String profileTag = 'mobile',
    String? format,
  }) async {
    final pusherData = <String, dynamic>{'url': url};
    if ((format ?? '').trim().isNotEmpty) {
      pusherData['format'] = format;
    }

    await _requestJson(
      method: 'POST',
      uri: _clientUri('/pushers/set'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        'kind': 'http',
        'app_id': appId,
        'app_display_name': appDisplayName,
        'device_display_name': deviceDisplayName,
        'pushkey': pushKey,
        'lang': lang,
        'profile_tag': profileTag,
        'data': pusherData,
      }),
    );
  }

  Future<void> deletePusher({
    required String pushKey,
    required String appId,
  }) async {
    await _requestJson(
      method: 'POST',
      uri: _clientUri('/pushers/set'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        'kind': null,
        'app_id': appId,
        'pushkey': pushKey,
      }),
    );
  }

  Future<String> sendText(
    String roomId,
    String body, {
    String? replyToEventId,
  }) async {
    final txId = _txnId();
    final payload = <String, dynamic>{'msgtype': 'm.text', 'body': body};
    if (replyToEventId != null && replyToEventId.isNotEmpty) {
      payload['m.relates_to'] = {
        'm.in_reply_to': {'event_id': replyToEventId},
      };
    }

    final res = await _requestJson(
      method: 'PUT',
      uri: _clientUri('/rooms/$roomId/send/m.room.message/$txId'),
      headers: _authHeaders(),
      body: jsonEncode(payload),
    );
    return (res['event_id'] ?? '').toString();
  }

  Future<String> editText(String roomId, String eventId, String newBody) async {
    final txId = _txnId();
    final payload = {
      'msgtype': 'm.text',
      'body': '* $newBody',
      'm.new_content': {'msgtype': 'm.text', 'body': newBody},
      'm.relates_to': {'rel_type': 'm.replace', 'event_id': eventId},
    };

    final res = await _requestJson(
      method: 'PUT',
      uri: _clientUri('/rooms/$roomId/send/m.room.message/$txId'),
      headers: _authHeaders(),
      body: jsonEncode(payload),
    );
    return (res['event_id'] ?? '').toString();
  }

  Future<String> uploadMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    final uri = _mediaUri('/upload', {'filename': filename});
    final response = await _http.post(
      uri,
      headers: _authHeaders(extra: {'content-type': mimeType}, json: false),
      body: bytes,
    );
    final jsonMap = await _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawBody = response.body;
      final isHtmlError = rawBody.trimLeft().startsWith('<');
      final message = jsonMap['error'] ?? 'HTTP ${response.statusCode}';
      final detail = isHtmlError
          ? 'HTTP ${response.statusCode} HTML error: ${_responseSnippet(rawBody)}'
          : '$message';
      throw StateError('Media upload failed: $detail');
    }
    return (jsonMap['content_uri'] ?? '').toString();
  }

  Future<String> sendMediaMessage({
    required String roomId,
    required String msgtype,
    required String body,
    required String mxcUrl,
    required String mimeType,
    String? caption,
    bool isForwarded = false,
  }) async {
    final txId = _txnId();
    final payload = <String, dynamic>{
      'msgtype': msgtype,
      'body': body,
      'url': mxcUrl,
      'info': {'mimetype': mimeType},
    };
    if ((caption ?? '').trim().isNotEmpty) {
      payload['org.cluborbit.caption'] = caption!.trim();
    }
    if (isForwarded) {
      payload['org.cluborbit.forwarded'] = true;
    }

    final res = await _requestJson(
      method: 'PUT',
      uri: _clientUri('/rooms/$roomId/send/m.room.message/$txId'),
      headers: _authHeaders(),
      body: jsonEncode(payload),
    );
    return (res['event_id'] ?? '').toString();
  }

  Future<void> sendReaction({
    required String roomId,
    required String eventId,
    required String emoji,
  }) async {
    final txId = _txnId();
    await _requestJson(
      method: 'PUT',
      uri: _clientUri('/rooms/$roomId/send/m.reaction/$txId'),
      headers: _authHeaders(),
      body: jsonEncode({
        'm.relates_to': {
          'rel_type': 'm.annotation',
          'event_id': eventId,
          'key': emoji,
        },
      }),
    );
  }

  Future<void> redact({
    required String roomId,
    required String eventId,
    String? reason,
  }) async {
    final txId = _txnId();
    await _requestJson(
      method: 'PUT',
      uri: _clientUri('/rooms/$roomId/redact/$eventId/$txId'),
      headers: _authHeaders(),
      body: jsonEncode({
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason,
      }),
    );
  }

  Future<void> setTyping({
    required String roomId,
    required bool isTyping,
    int timeoutMs = 15000,
  }) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    await _requestJson(
      method: 'PUT',
      uri: _clientUri('/rooms/$roomId/typing/${Uri.encodeComponent(userId)}'),
      headers: _authHeaders(),
      body: jsonEncode({'typing': isTyping, 'timeout': timeoutMs}),
    );
  }

  Future<void> setReadMarker({
    required String roomId,
    required String eventId,
  }) async {
    await _requestJson(
      method: 'POST',
      uri: _clientUri('/rooms/$roomId/read_markers'),
      headers: _authHeaders(),
      body: jsonEncode({'m.fully_read': eventId, 'm.read': eventId}),
    );
  }

  Future<MatrixTurnServerConfig> getTurnServerConfig() async {
    final res = await _requestJson(
      method: 'GET',
      uri: _clientUri('/voip/turnServer'),
      headers: _authHeaders(json: false),
    );
    final uris =
        (res['uris'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];

    return MatrixTurnServerConfig(
      uris: uris,
      username: (res['username'] ?? '').toString(),
      password: (res['password'] ?? '').toString(),
      ttl: (res['ttl'] is int) ? res['ttl'] as int : 0,
    );
  }

  Future<String> sendCallEvent({
    required String roomId,
    required String eventType,
    required Map<String, dynamic> content,
  }) async {
    final txId = _txnId();
    final res = await _requestJson(
      method: 'PUT',
      uri: _clientUri('/rooms/$roomId/send/$eventType/$txId'),
      headers: _authHeaders(),
      body: jsonEncode(content),
    );
    return (res['event_id'] ?? '').toString();
  }

  Future<String> createRoom({
    required String name,
    required List<String> invite,
    required bool isDirect,
    List<Map<String, dynamic>> initialState = const <Map<String, dynamic>>[],
  }) async {
    final payload = <String, dynamic>{
      'preset': isDirect ? 'trusted_private_chat' : 'private_chat',
      'is_direct': isDirect,
      'invite': invite,
      if (name.trim().isNotEmpty) 'name': name,
    };
    if (initialState.isNotEmpty) {
      payload['initial_state'] = initialState;
    }
    final res = await _requestJson(
      method: 'POST',
      uri: _clientUri('/createRoom'),
      headers: _authHeaders(),
      body: jsonEncode(payload),
    );
    return (res['room_id'] ?? '').toString();
  }

  String mxcToThumbnailHttp(Uri? uri) {
    if (uri == null || uri.scheme != 'mxc') return '';
    return '$_homeserver/_matrix/media/v3/thumbnail/${uri.host}${uri.path}?width=96&height=96&method=crop';
  }

  String mxcToDownloadHttp(Uri? uri) {
    if (uri == null || uri.scheme != 'mxc') return '';
    return '$_homeserver/_matrix/media/v3/download/${uri.host}${uri.path}';
  }

  Future<List<int>> downloadMedia(String downloadUrl) async {
    if (_disposed) {
      throw StateError('Matrix HTTP client is disposed');
    }
    final response = await _http.get(
      Uri.parse(downloadUrl),
      headers: _authHeaders(json: false),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Media download failed (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  // Verification methods (backend-assisted key verification).

  /// Initiates a key verification request with another user.
  /// Returns the verification transaction ID.
  Future<String> startVerification({required String userId}) async {
    final txId = const Uuid().v4();
    final payload = {
      'method': 'm.sas.v1',
      'from_device': _deviceId ?? 'PlayerChat',
      'transaction_id': txId,
    };

    final sessionId = '${userId}_$txId';
    _verificationSessions[sessionId] = {
      'id': sessionId,
      'userId': userId,
      'transactionId': txId,
      'state': 'requested',
      'isDone': false,
      'createdAt': DateTime.now().toIso8601String(),
    };

    // In a real backend-assisted setup, send this to the server or to_device queue.
    // For now, we track locally and the backend can subscribe to verification events.
    try {
      await _requestJson(
        method: 'POST',
        uri: _clientUri('/user/${Uri.encodeComponent(userId)}/verify'),
        headers: _authHeaders(),
        body: jsonEncode(payload),
      );
    } catch (_) {
      // If explicit endpoint doesn't exist, continue with local tracking.
      // The backend may handle verification through other channels.
    }

    return sessionId;
  }

  /// Accepts a pending key verification.
  Future<void> acceptVerification(String verificationId) async {
    if (!_verificationSessions.containsKey(verificationId)) {
      throw StateError('Verification session not found: $verificationId');
    }

    final session = _verificationSessions[verificationId]!;
    session['state'] = 'accepted';

    try {
      await _requestJson(
        method: 'POST',
        uri: _clientUri(
          '/user/${Uri.encodeComponent(session['userId'])}/verify/accept',
        ),
        headers: _authHeaders(),
        body: jsonEncode({'transaction_id': session['transactionId']}),
      );
    } catch (_) {
      // Verification acceptance recorded locally if backend endpoint unavailable.
    }
  }

  /// Rejects a pending key verification.
  Future<void> rejectVerification(String verificationId) async {
    if (!_verificationSessions.containsKey(verificationId)) {
      throw StateError('Verification session not found: $verificationId');
    }

    final session = _verificationSessions[verificationId]!;
    session['state'] = 'cancelled';
    session['isDone'] = true;

    try {
      await _requestJson(
        method: 'POST',
        uri: _clientUri(
          '/user/${Uri.encodeComponent(session['userId'])}/verify/reject',
        ),
        headers: _authHeaders(),
        body: jsonEncode({'transaction_id': session['transactionId']}),
      );
    } catch (_) {
      // Rejection recorded locally if backend endpoint unavailable.
    }
  }

  /// Accepts SAS (Short Authentication String) verification.
  Future<void> acceptSas(String verificationId) async {
    if (!_verificationSessions.containsKey(verificationId)) {
      throw StateError('Verification session not found: $verificationId');
    }

    final session = _verificationSessions[verificationId]!;
    session['state'] = 'verified';

    try {
      await _requestJson(
        method: 'POST',
        uri: _clientUri(
          '/user/${Uri.encodeComponent(session['userId'])}/verify/sas/accept',
        ),
        headers: _authHeaders(),
        body: jsonEncode({'transaction_id': session['transactionId']}),
      );
    } catch (_) {
      // SAS acceptance recorded locally.
    }
  }

  /// Rejects SAS verification.
  Future<void> rejectSas(String verificationId) async {
    if (!_verificationSessions.containsKey(verificationId)) {
      throw StateError('Verification session not found: $verificationId');
    }

    final session = _verificationSessions[verificationId]!;
    session['state'] = 'cancelled';
    session['isDone'] = true;

    try {
      await _requestJson(
        method: 'POST',
        uri: _clientUri(
          '/user/${Uri.encodeComponent(session['userId'])}/verify/sas/reject',
        ),
        headers: _authHeaders(),
        body: jsonEncode({'transaction_id': session['transactionId']}),
      );
    } catch (_) {
      // Rejection recorded locally.
    }
  }

  /// Returns all active verification sessions.
  List<Map<String, dynamic>> getVerificationSessions() {
    return _verificationSessions.values
        .where((session) => session['isDone'] != true)
        .toList(growable: false);
  }

  void dispose() {
    _disposed = true;
    _http.close();
  }
}
