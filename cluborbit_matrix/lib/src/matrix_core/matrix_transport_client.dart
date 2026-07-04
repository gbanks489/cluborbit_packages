class MatrixTransportCapabilities {
  const MatrixTransportCapabilities({
    required this.transportId,
    required this.supportsRoomEncryptionState,
    required this.supportsDeviceKeys,
    required this.supportsMegolmEncryption,
    required this.supportsMegolmDecryption,
  });

  final String transportId;
  final bool supportsRoomEncryptionState;
  final bool supportsDeviceKeys;
  final bool supportsMegolmEncryption;
  final bool supportsMegolmDecryption;

  bool get isCryptoCapable {
    return supportsDeviceKeys &&
        supportsMegolmEncryption &&
        supportsMegolmDecryption;
  }
}

class MatrixLowLevelLoginResult {
  const MatrixLowLevelLoginResult({
    required this.userId,
    required this.accessToken,
    this.deviceId,
  });

  final String userId;
  final String accessToken;
  final String? deviceId;
}

class MatrixTurnServerConfig {
  const MatrixTurnServerConfig({
    required this.uris,
    required this.username,
    required this.password,
    required this.ttl,
  });

  final List<String> uris;
  final String username;
  final String password;
  final int ttl;
}

typedef MatrixTransportFactory =
    MatrixTransportClient Function({
      required String homeserver,
      required String clientName,
    });

abstract class MatrixTransportClient {
  MatrixTransportCapabilities get capabilities;
  String? get currentUserId;
  bool get isLoggedIn;
  String? get sinceToken;

  void restoreSinceToken(String? token);

  Future<MatrixLowLevelLoginResult> loginPassword({
    required String username,
    required String password,
    String initialDeviceDisplayName = 'PlayerChat REST Client',
  });

  Future<void> logout();

  Future<Map<String, dynamic>> sync({
    int timeoutMs = 0,
    bool fullState = false,
  });

  Future<Map<String, dynamic>> getRoomMessagesRaw(
    String roomId, {
    int limit = 60,
  });

  Future<Map<String, dynamic>> getEvent(String roomId, String eventId);
  Future<Map<String, dynamic>> getPresenceStatus(String userId);
  Future<Map<String, dynamic>> getState(String roomId);
  Future<List<dynamic>> getStateEvents(String roomId);
  Future<String> resolveRoomAlias(String roomAlias);
  Future<Map<String, dynamic>> getMembers(String roomId);
  Future<void> joinRoom(String roomId);
  Future<void> leaveRoom(String roomId);
  Future<void> setRoomAvatar(String roomId, String mxcUrl);

  Future<void> setHttpPusher({
    required String pushKey,
    required String appId,
    required String appDisplayName,
    required String deviceDisplayName,
    required String url,
    String lang = 'en',
    String profileTag = 'mobile',
    String? format,
  });

  Future<void> deletePusher({required String pushKey, required String appId});

  Future<String> sendText(String roomId, String body, {String? replyToEventId});

  Future<String> editText(String roomId, String eventId, String newBody);

  Future<String> uploadMedia({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  });

  Future<String> sendMediaMessage({
    required String roomId,
    required String msgtype,
    required String body,
    required String mxcUrl,
    required String mimeType,
    String? caption,
    bool isForwarded = false,
  });

  Future<void> sendReaction({
    required String roomId,
    required String eventId,
    required String emoji,
  });

  Future<void> redact({
    required String roomId,
    required String eventId,
    String? reason,
  });

  Future<void> setTyping({
    required String roomId,
    required bool isTyping,
    int timeoutMs = 15000,
  });

  Future<void> setReadMarker({required String roomId, required String eventId});

  Future<MatrixTurnServerConfig> getTurnServerConfig();

  Future<String> sendCallEvent({
    required String roomId,
    required String eventType,
    required Map<String, dynamic> content,
  });

  Future<String> createRoom({
    required String name,
    required List<String> invite,
    required bool isDirect,
    List<Map<String, dynamic>> initialState = const <Map<String, dynamic>>[],
  });

  String mxcToThumbnailHttp(Uri? uri);
  String mxcToDownloadHttp(Uri? uri);
  Future<List<int>> downloadMedia(String downloadUrl);
  Future<String> startVerification({required String userId});
  Future<void> acceptVerification(String verificationId);
  Future<void> rejectVerification(String verificationId);
  Future<void> acceptSas(String verificationId);
  Future<void> rejectSas(String verificationId);
  List<Map<String, dynamic>> getVerificationSessions();
  void dispose();
}
