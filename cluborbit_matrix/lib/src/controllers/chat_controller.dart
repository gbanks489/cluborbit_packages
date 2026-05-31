import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cluborbit_models/cluborbit_models.dart';
import 'package:clubcommon/clubcommon.dart';

import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/incoming_call_settings_store.dart';
import '../services/matrix_rest_service.dart';
import '../services/user_profile_service.dart';

class IncomingCallUxSettings {
  const IncomingCallUxSettings({
    required this.autoOpenFullScreen,
    required this.ringtoneEnabled,
    required this.vibrationEnabled,
  });

  static const IncomingCallUxSettings defaults = IncomingCallUxSettings(
    autoOpenFullScreen: true,
    ringtoneEnabled: true,
    vibrationEnabled: true,
  );

  final bool autoOpenFullScreen;
  final bool ringtoneEnabled;
  final bool vibrationEnabled;

  IncomingCallUxSettings copyWith({
    bool? autoOpenFullScreen,
    bool? ringtoneEnabled,
    bool? vibrationEnabled,
  }) {
    return IncomingCallUxSettings(
      autoOpenFullScreen: autoOpenFullScreen ?? this.autoOpenFullScreen,
      ringtoneEnabled: ringtoneEnabled ?? this.ringtoneEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }
}

class ChatController extends ChangeNotifier {
  static const int _maxUploadBytes = 10 * 1024 * 1024;

  ChatController({
    required AuthService authService,
    required MatrixRestService matrixService,
    required ConnectivityService connectivityService,
    required ErrorNotifier errorNotifier,
    required UserProfileService userProfileService,
    IncomingCallSettingsStore? incomingCallSettingsStore,
  }) : _authService = authService,
       _matrixService = matrixService,
       _connectivityService = connectivityService,
       _errorNotifier = errorNotifier,
       _userProfileService = userProfileService,
       _incomingCallSettingsStore =
           incomingCallSettingsStore ?? IncomingCallSettingsStore() {
    unawaited(_hydrateIncomingCallUxSettings());
  }

  final AuthService _authService;
  final MatrixRestService _matrixService;
  final ConnectivityService _connectivityService;
  final ErrorNotifier _errorNotifier;
  final UserProfileService _userProfileService;
  final IncomingCallSettingsStore _incomingCallSettingsStore;

  StreamSubscription<void>? _syncSubscription;

  bool _loading = false;
  bool _matrixConnecting = false;
  double _matrixSyncProgress = 0;
  String _matrixSyncStatus = 'Preparing chats...';
  String? _lastBackgroundConnectAttemptUid;
  String _query = '';
  int _searchRequestId = 0;
  String? _activeRoomId;
  String? _activeRoomTitle;
  List<ChatThread> _threads = const <ChatThread>[];
  List<ChatParticipant> _searchedUsers = const <ChatParticipant>[];
  List<ChatMessage> _messages = const <ChatMessage>[];
  List<ChatParticipant> _participants = const <ChatParticipant>[];
  List<ChatParticipant> _typingUsers = const <ChatParticipant>[];
  List<VerificationSession> _verificationSessions =
      const <VerificationSession>[];
  ChatEncryptionStatus _activeRoomEncryptionStatus =
      const ChatEncryptionStatus.unencrypted();
  ChatMessage? _replyToMessage;
  User? _userProfile;
  IncomingCallUxSettings _incomingCallUxSettings =
      IncomingCallUxSettings.defaults;

  bool get loading => _loading;
  bool get matrixConnecting => _matrixConnecting;
  int get matrixSyncPercent =>
      (_matrixSyncProgress * 100).round().clamp(0, 100);
  String get matrixSyncStatus => _matrixSyncStatus;
  bool get hasFirebaseSession => _authService.currentUser != null;
  String get query => _query;
  String get currentUserId =>
      _authService.currentUser?.uid ?? _matrixService.currentUserId ?? '';
  String get matrixUserId => _matrixService.currentUserId ?? '';
  String? get activeRoomId => _activeRoomId;
  String? get activeRoomTitle => _activeRoomTitle;
  ChatEncryptionStatus get activeRoomEncryptionStatus =>
      _activeRoomEncryptionStatus;
  String? get activeRoomAvatarUrl {
    final roomId = _activeRoomId;
    if (roomId == null) {
      return null;
    }
    for (final thread in _threads) {
      if (thread.id == roomId) {
        return thread.avatarUrl;
      }
    }
    return null;
  }

  ChatType get activeRoomType {
    final roomId = _activeRoomId;
    if (roomId == null) {
      return ChatType.dm;
    }
    for (final thread in _threads) {
      if (thread.id == roomId) {
        return thread.type;
      }
    }
    return ChatType.dm;
  }

  List<ChatThread> get threads {
    if (_query.trim().isEmpty) {
      return _threads;
    }
    final q = _query.toLowerCase();
    return _threads
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              (t.lastMessage ?? '').toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  List<ChatParticipant> get searchedUsers => _searchedUsers;

  List<ChatMessage> get messages => _messages;
  List<ChatParticipant> get participants => _participants;
  List<ChatParticipant> get typingUsers => _typingUsers;
  ChatMessage? get replyToMessage => _replyToMessage;
  List<VerificationSession> get verificationSessions => _verificationSessions;
  User? get userProfile => _userProfile;
  Stream<ChatCallSnapshot> get callUpdates => _matrixService.callUpdates;
  Stream<void> get callMediaUpdates => _matrixService.callMediaUpdates;
  ChatCallSnapshot get callSnapshot => _matrixService.callSnapshot;
  RTCVideoRenderer? get localCallVideoRenderer =>
      _matrixService.localVideoRenderer;
  RTCVideoRenderer? get remoteCallVideoRenderer =>
      _matrixService.remoteVideoRenderer;
  IncomingCallUxSettings get incomingCallUxSettings => _incomingCallUxSettings;

  void setAutoOpenIncomingFullScreen(bool enabled) {
    _incomingCallUxSettings = _incomingCallUxSettings.copyWith(
      autoOpenFullScreen: enabled,
    );
    unawaited(_persistIncomingCallUxSettings());
    notifyListeners();
  }

  void setIncomingRingtoneEnabled(bool enabled) {
    _incomingCallUxSettings = _incomingCallUxSettings.copyWith(
      ringtoneEnabled: enabled,
    );
    unawaited(_persistIncomingCallUxSettings());
    notifyListeners();
  }

  void setIncomingVibrationEnabled(bool enabled) {
    _incomingCallUxSettings = _incomingCallUxSettings.copyWith(
      vibrationEnabled: enabled,
    );
    unawaited(_persistIncomingCallUxSettings());
    notifyListeners();
  }

  void resetIncomingCallUxSettingsToDefaults() {
    _incomingCallUxSettings = IncomingCallUxSettings.defaults;
    unawaited(_persistIncomingCallUxSettings());
    notifyListeners();
  }

  Future<void> _hydrateIncomingCallUxSettings() async {
    try {
      final loaded = await _incomingCallSettingsStore.load();
      _incomingCallUxSettings = loaded;
      notifyListeners();
    } catch (e, s) {
      debugPrint('Failed to load incoming call UX settings: $e\n$s');
    }
  }

  Future<void> _persistIncomingCallUxSettings() async {
    try {
      await _incomingCallSettingsStore.save(_incomingCallUxSettings);
    } catch (e, s) {
      debugPrint('Failed to persist incoming call UX settings: $e\n$s');
    }
  }

  Future<void> refreshCurrentUserProfile() async {
    try {
      _userProfile = await _userProfileService.fetchCurrentUserProfile();
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> updateCurrentUserProfile({
    required User profile,
    Uint8List? imageBytes,
    Uint8List? coverImageBytes,
  }) async {
    _setLoading(true);
    try {
      _userProfile = await _userProfileService.saveCurrentUserProfile(
        profile: profile,
        imageBytes: imageBytes,
        coverImageBytes: coverImageBytes,
      );
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  void updateSearchQuery(String value) {
    _query = value;
    final trimmed = value.trim();
    final excludeUserId = matrixUserId.isNotEmpty
        ? matrixUserId
        : currentUserId;
    final requestId = ++_searchRequestId;
    if (trimmed.isEmpty) {
      _searchedUsers = const <ChatParticipant>[];
      notifyListeners();
      return;
    }

    _matrixService
        .searchUsers(trimmed, excludeUserId: excludeUserId)
        .then((users) {
          if (requestId != _searchRequestId || trimmed != _query.trim()) {
            return;
          }
          _searchedUsers = users;
          notifyListeners();
        })
        .catchError((_) {
          if (requestId != _searchRequestId || trimmed != _query.trim()) {
            return;
          }
          _searchedUsers = const <ChatParticipant>[];
          notifyListeners();
        });

    notifyListeners();
  }

  void clearSearchState({bool notify = true}) {
    _query = '';
    _searchedUsers = const <ChatParticipant>[];
    _searchRequestId++;
    if (notify) {
      notifyListeners();
    }
  }

  Future<List<ChatParticipant>> searchUsers(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return Future.value(const <ChatParticipant>[]);
    }
    final excludeUserId = matrixUserId.isNotEmpty
        ? matrixUserId
        : currentUserId;
    return _matrixService.searchUsers(trimmed, excludeUserId: excludeUserId);
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      await _authService.loginUserWithPassword(
        email: email,
        password: password,
      );
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signInWithGoogle() async {
    _setLoading(true);
    try {
      await _authService.googleLogin();
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      await _authService.registerWithPassword(email: email, password: password);
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signUpCreateProfileAndConnect({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String displayName,
    required String gender,
    required DateTime dateOfBirth,
    Uint8List? imageBytes,
  }) async {
    _setLoading(true);
    try {
      await _authService.registerWithPassword(email: email, password: password);

      await saveOnboardingProfile(
        firstName: firstName,
        lastName: lastName,
        displayName: displayName,
        gender: gender,
        activities: const <String>[],
        dateOfBirth: IsoDateTime(dateOfBirth),
        imageBytes: imageBytes,
      );

      await connectMatrixUsingProfile();
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signInAndConnectWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      await _authService.loginUserWithPassword(
        email: email,
        password: password,
      );
      await connectMatrixUsingProfile();
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signInAndConnectWithGoogle() async {
    _setLoading(true);
    try {
      await _authService.googleLogin();
      await connectMatrixUsingProfile();
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> connectMatrixUsingProfileInBackground() async {
    final firebaseUserId = _authService.currentUser?.uid;
    if (firebaseUserId == null) {
      return;
    }
    if (_matrixConnecting || _matrixService.currentUserId != null) {
      return;
    }
    if (_lastBackgroundConnectAttemptUid == firebaseUserId) {
      return;
    }
    _lastBackgroundConnectAttemptUid = firebaseUserId;

    _setMatrixConnecting(
      true,
      progress: 0.08,
      status: 'Fetching chat profile...',
    );
    var connected = false;
    String? failureMessage;
    try {
      final creds = await _userProfileService
          .fetchMatrixCredentialsFromProfile();
      _userProfile = creds.profile;
      _updateMatrixSyncProgress(0.2, 'Checking chat server...');
      await _connectMatrixInternal(
        username: creds.matrixUserId,
        password: creds.matrixPassword,
      );
      connected = true;
      _errorNotifier.clear();
    } catch (e) {
      failureMessage = _describeError(e);
      _errorNotifier.setError(failureMessage);
    } finally {
      _setMatrixConnecting(
        false,
        progress: connected ? 1 : 0,
        status: connected
            ? 'Chats ready'
            : (failureMessage ?? 'Chat connection failed'),
      );
    }
  }

  Future<bool> tryAutoLoginAndConnect() async {
    if (_authService.currentUser == null) {
      return false;
    }

    _setLoading(true);
    try {
      final creds = await _userProfileService
          .fetchMatrixCredentialsFromProfile();
      _userProfile = creds.profile;
      await _connectMatrixInternal(
        username: creds.matrixUserId,
        password: creds.matrixPassword,
      );
      _errorNotifier.clear();
      return true;
    } catch (e) {
      _errorNotifier.setError(e.toString());
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    _setLoading(true);
    try {
      await _syncSubscription?.cancel();
      _syncSubscription = null;
      _lastBackgroundConnectAttemptUid = null;
      _setMatrixConnecting(false, progress: 0, status: 'Preparing chats...');
      await _matrixService.logout();
      await _authService.signOut();

      _query = '';
      _activeRoomId = null;
      _activeRoomTitle = null;
      _threads = const <ChatThread>[];
      _searchedUsers = const <ChatParticipant>[];
      _messages = const <ChatMessage>[];
      _participants = const <ChatParticipant>[];
      _typingUsers = const <ChatParticipant>[];
      _verificationSessions = const <VerificationSession>[];
      _activeRoomEncryptionStatus = const ChatEncryptionStatus.unencrypted();
      _replyToMessage = null;
      _userProfile = null;
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<bool> isOnboardingRequired() async {
    _setLoading(true);
    try {
      final profile = await _userProfileService.fetchCurrentUserProfile();
      _userProfile = profile;
      _errorNotifier.clear();
      return profile == null;
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> saveOnboardingProfile({
    required String firstName,
    required String lastName,
    required String displayName,
    String? gender,
    String? bio,
    String? city,
    String? province,
    String? country,
    List<String> activities = const <String>[],
    IsoDateTime? dateOfBirth,
    Uint8List? imageBytes,
  }) async {
    final user = _authService.currentUser;
    if (user == null) {
      throw Exception('You must sign in before onboarding.');
    }

    _setLoading(true);
    try {
      final profile = User(
        uid: user.uid,
        email: user.email ?? '',
        firstName: firstName,
        lastName: lastName,
        displayName: displayName,
        dateOfBirth: dateOfBirth,
        gender: _parseGender(gender),
        bio: bio,
        activities: activities,
      );
      _userProfile = await _userProfileService.saveCurrentUserProfile(
        profile: profile,
        imageBytes: imageBytes,
      );
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Gender? _parseGender(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'male':
        return Gender.male;
      case 'female':
        return Gender.female;
      case 'other':
        return Gender.other;
      default:
        return null;
    }
  }

  Future<void> connectMatrix({
    required String username,
    required String password,
  }) async {
    _setLoading(true);
    try {
      await _connectMatrixInternal(username: username, password: password);
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> connectMatrixUsingProfile() async {
    _setLoading(true);
    try {
      _updateMatrixSyncProgress(0.08, 'Fetching chat profile...');
      final creds = await _userProfileService
          .fetchMatrixCredentialsFromProfile();
      _userProfile = creds.profile;
      _updateMatrixSyncProgress(0.2, 'Checking chat server...');
      await _connectMatrixInternal(
        username: creds.matrixUserId,
        password: creds.matrixPassword,
      );
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadThreads({
    void Function(double progress, String status)? onProgress,
  }) async {
    _setLoading(true);
    try {
      _threads = await _matrixService.getJoinedThreads(onProgress: onProgress);
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> openRoom(String roomId, {String? roomTitle}) async {
    _activeRoomId = roomId;
    _activeRoomTitle = roomTitle;
    _setLoading(true);
    try {
      _messages = await _matrixService.getRoomMessages(roomId);
      await _matrixService.setReadMarker(roomId);
      _participants = await _matrixService.getRoomParticipants(roomId);
      _typingUsers = await _matrixService.getTypingUsers(roomId);
      _activeRoomEncryptionStatus = await _matrixService
          .getRoomEncryptionStatus(roomId);
      _verificationSessions = _matrixService.getVerificationSessions();
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  void openRoomInBackground(String roomId, {String? roomTitle}) {
    unawaited(
      openRoom(roomId, roomTitle: roomTitle).catchError((Object error) {
        _errorNotifier.setError(error.toString());
      }),
    );
  }

  Future<bool> joinRoomIfInvited(String roomId) {
    return _matrixService.joinRoomIfInvited(roomId);
  }

  Future<void> refreshChatDetails() async {
    final roomId = _activeRoomId;
    if (roomId == null) {
      return;
    }
    _participants = await _matrixService.getRoomParticipants(roomId);
    _activeRoomEncryptionStatus = await _matrixService.getRoomEncryptionStatus(
      roomId,
    );
    _verificationSessions = _matrixService.getVerificationSessions();
    notifyListeners();
  }

  Future<void> refreshFromPush({String? roomId}) async {
    if (!hasFirebaseSession) {
      return;
    }
    if (matrixUserId.isEmpty) {
      await connectMatrixUsingProfileInBackground();
      return;
    }

    await _refreshFromSync();

    final normalizedRoomId = roomId?.trim();
    if (normalizedRoomId != null &&
        normalizedRoomId.isNotEmpty &&
        normalizedRoomId == _activeRoomId) {
      try {
        await _matrixService.setReadMarker(normalizedRoomId);
      } catch (_) {
        // Push-driven read markers are best-effort.
      }
    }
  }

  Future<void> sendText(String text) async {
    final roomId = _activeRoomId;
    if (roomId == null || text.trim().isEmpty) {
      return;
    }

    final trimmed = text.trim();
    final replyTarget = _replyToMessage;
    final optimistic = _matrixService.createOptimisticTextMessage(
      roomId: roomId,
      body: trimmed,
      kind: MessageKind.text,
      replyToEventId: replyTarget?.id,
      replyToSenderName: replyTarget?.senderName,
      replyToBody: replyTarget?.body,
    );
    _replyToMessage = null;
    _messages = _mergeActiveMessages(<ChatMessage>[optimistic]);
    notifyListeners();
    unawaited(_matrixService.setTyping(roomId: roomId, isTyping: false));
    unawaited(
      _sendOptimisticTextMessage(
        optimistic: optimistic,
        text: trimmed,
        replyToEventId: replyTarget?.id,
      ),
    );
  }

  Future<void> sendEmoji(String emoji) async {
    final roomId = _activeRoomId;
    if (roomId == null || emoji.trim().isEmpty) {
      return;
    }

    final trimmed = emoji.trim();
    final replyTarget = _replyToMessage;
    final optimistic = _matrixService.createOptimisticTextMessage(
      roomId: roomId,
      body: trimmed,
      kind: MessageKind.emoji,
      replyToEventId: replyTarget?.id,
      replyToSenderName: replyTarget?.senderName,
      replyToBody: replyTarget?.body,
    );
    _replyToMessage = null;
    _messages = _mergeActiveMessages(<ChatMessage>[optimistic]);
    notifyListeners();
    unawaited(_matrixService.setTyping(roomId: roomId, isTyping: false));
    unawaited(
      _sendOptimisticTextMessage(
        optimistic: optimistic,
        text: trimmed,
        replyToEventId: replyTarget?.id,
      ),
    );
  }

  Future<void> _sendOptimisticTextMessage({
    required ChatMessage optimistic,
    required String text,
    String? replyToEventId,
  }) async {
    try {
      final sent = await _matrixService.sendStagedTextMessage(
        optimisticMessage: optimistic,
        text: text,
        replyToEventId: replyToEventId,
      );
      _messages = _replaceActiveMessage(
        previousId: optimistic.id,
        replacement: sent,
      );
      notifyListeners();
    } catch (e) {
      _matrixService.markStagedMessageFailed(optimistic);
      _messages = _replaceActiveMessage(
        previousId: optimistic.id,
        replacement: optimistic.copyWith(
          metadata: <String, dynamic>{
            ...optimistic.metadata,
            'sendStage': 'failed',
          },
        ),
      );
      _errorNotifier.setError(e.toString());
      notifyListeners();
    }
  }

  List<ChatMessage> _mergeActiveMessages(List<ChatMessage> incoming) {
    final byId = <String, ChatMessage>{
      for (final message in _messages) message.id: message,
    };
    for (final message in incoming) {
      byId[message.id] = message;
    }
    final merged = byId.values.toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  List<ChatMessage> _replaceActiveMessage({
    required String previousId,
    required ChatMessage replacement,
  }) {
    final retained = _messages
        .where((message) => message.id != previousId)
        .toList(growable: false);
    final byId = <String, ChatMessage>{
      for (final message in retained) message.id: message,
      replacement.id: replacement,
    };
    final merged = byId.values.toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  Future<void> setTyping(bool isTyping) async {
    final roomId = _activeRoomId;
    if (roomId == null) {
      return;
    }
    try {
      await _matrixService.setTyping(roomId: roomId, isTyping: isTyping);
      _typingUsers = await _matrixService.getTypingUsers(roomId);
    } catch (_) {
      // Best-effort only; keep chat input responsive.
    }
    notifyListeners();
  }

  void setReplyTarget(ChatMessage message) {
    _replyToMessage = message;
    notifyListeners();
  }

  void clearReplyTarget() {
    _replyToMessage = null;
    notifyListeners();
  }

  Future<void> editMessage({
    required String eventId,
    required String updatedText,
  }) async {
    final roomId = _activeRoomId;
    if (roomId == null || updatedText.trim().isEmpty) {
      return;
    }

    await _matrixService.editMessage(
      roomId: roomId,
      originalEventId: eventId,
      newBody: updatedText.trim(),
    );
    await openRoom(roomId, roomTitle: _activeRoomTitle);
  }

  Future<void> forwardMessage({
    required ChatMessage source,
    required String targetRoomId,
  }) async {
    await _matrixService.forwardMessage(roomId: targetRoomId, source: source);
  }

  Future<String> createDm(String userId, {String? roomTitle}) async {
    final roomId = await _matrixService.createDirectMessage(
      otherUserId: userId,
    );
    _activeRoomId = roomId;
    _activeRoomTitle = roomTitle;
    _messages = const <ChatMessage>[];
    _participants = const <ChatParticipant>[];
    _typingUsers = const <ChatParticipant>[];
    _verificationSessions = const <VerificationSession>[];
    _activeRoomEncryptionStatus = const ChatEncryptionStatus.unencrypted();
    notifyListeners();

    unawaited(loadThreads());
    openRoomInBackground(roomId, roomTitle: roomTitle);
    return roomId;
  }

  Future<ChatUserPresence> getUserPresence(String userId) {
    return _matrixService.getUserPresence(userId);
  }

  ChatUserPresence? cachedUserPresence(String userId) {
    return _matrixService.cachedUserPresence(userId);
  }

  ChatParticipant? cachedDirectMessageCounterpart(String roomId) {
    return _matrixService.cachedDirectMessageCounterpart(roomId);
  }

  Future<List<ChatParticipant>> getRoomParticipants(
    String roomId, {
    bool forceRefresh = false,
  }) {
    return _matrixService.getRoomParticipants(
      roomId,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> deleteMessage(String eventId) async {
    final roomId = _activeRoomId;
    if (roomId == null) return;
    await _matrixService.redactEvent(roomId: roomId, eventId: eventId);
    await openRoom(roomId, roomTitle: _activeRoomTitle);
  }

  Future<void> sendReaction(String eventId, String emoji) async {
    final roomId = _activeRoomId;
    if (roomId == null) return;
    await _matrixService.sendReaction(
      roomId: roomId,
      eventId: eventId,
      emoji: emoji,
    );
  }

  Future<void> voteOnPoll(
    ChatMessage message,
    int optionIndex, {
    required bool allowsMultiple,
  }) async {
    final roomId = _activeRoomId;
    final userId = matrixUserId;
    if (roomId == null || userId.isEmpty) {
      return;
    }

    final pollVotes =
        (message.metadata['pollVotes'] as List?) ?? const <dynamic>[];
    final myVotes = pollVotes
        .whereType<Map>()
        .where((vote) => (vote['senderId'] ?? '').toString() == userId)
        .toList(growable: false);
    final existingOptions = myVotes
        .map((vote) => vote['optionIndex'])
        .whereType<int>()
        .toList(growable: false);
    final alreadySelected = existingOptions.contains(optionIndex);

    final priorVoteEventIds =
        (allowsMultiple
                ? myVotes.where((vote) => vote['optionIndex'] == optionIndex)
                : myVotes)
            .map((vote) => (vote['eventId'] ?? '').toString())
            .where((eventId) => eventId.isNotEmpty)
            .toList(growable: false);

    await _matrixService.sendPollVote(
      roomId: roomId,
      eventId: message.id,
      optionIndex: optionIndex,
      priorVoteEventIds: priorVoteEventIds,
      sendVote: !alreadySelected,
    );
    await openRoom(roomId, roomTitle: _activeRoomTitle);
  }

  Future<void> startCall({required bool isVideo}) async {
    final roomId = _activeRoomId;
    if (roomId == null) {
      throw StateError('No active room selected for call.');
    }
    await _matrixService.startCall(roomId: roomId, isVideo: isVideo);
  }

  Future<void> answerCall() async {
    await _matrixService.answerActiveCall();
  }

  Future<void> rejectCall() async {
    await _matrixService.rejectActiveCall();
  }

  Future<void> hangupCall() async {
    await _matrixService.hangupActiveCall();
  }

  Future<void> setCallMicrophoneMuted(bool muted) async {
    await _matrixService.setMicrophoneMuted(muted);
  }

  Future<void> setCallVideoMuted(bool muted) async {
    await _matrixService.setVideoMuted(muted);
  }

  Future<void> setCallSpeakerOn(bool speakerOn) async {
    await _matrixService.setSpeakerOn(speakerOn);
  }

  void resetCallState() {
    _matrixService.resetCallState();
  }

  Future<void> createGroup({
    required String name,
    required List<String> members,
    Uint8List? avatarBytes,
    String? avatarFilename,
  }) async {
    final roomId = await _matrixService.createGroup(
      name: name,
      userIds: members,
      avatarBytes: avatarBytes,
      avatarFilename: avatarFilename,
      avatarMimeType: avatarFilename == null
          ? null
          : _mimeTypeFromFileName(avatarFilename),
    );
    await loadThreads();
    await openRoom(roomId, roomTitle: name);
  }

  Future<void> updateActiveRoomAvatar({
    required Uint8List avatarBytes,
    required String filename,
  }) async {
    final roomId = _activeRoomId;
    if (roomId == null) {
      throw StateError('No active room selected.');
    }

    final avatarUrl = await _matrixService.updateRoomAvatar(
      roomId: roomId,
      bytes: avatarBytes,
      filename: filename,
      mimeType: _mimeTypeFromFileName(filename),
    );

    if (avatarUrl != null) {
      _threads = _threads
          .map(
            (thread) => thread.id == roomId
                ? thread.copyWith(avatarUrl: avatarUrl)
                : thread,
          )
          .toList(growable: false);
      notifyListeners();
    }
  }

  Future<void> startKeyVerificationForUser(String userId) async {
    final roomId = _activeRoomId;
    await _matrixService.startKeyVerification(userId: userId, roomId: roomId);
    _verificationSessions = _matrixService.getVerificationSessions();
    notifyListeners();
  }

  Future<void> acceptVerification(String verificationId) async {
    await _matrixService.acceptVerification(verificationId);
    _verificationSessions = _matrixService.getVerificationSessions();
    notifyListeners();
  }

  Future<void> rejectVerification(String verificationId) async {
    await _matrixService.rejectVerification(verificationId);
    _verificationSessions = _matrixService.getVerificationSessions();
    notifyListeners();
  }

  Future<void> acceptSas(String verificationId) async {
    await _matrixService.acceptSas(verificationId);
    _verificationSessions = _matrixService.getVerificationSessions();
    notifyListeners();
  }

  Future<void> rejectSas(String verificationId) async {
    await _matrixService.rejectSas(verificationId);
    _verificationSessions = _matrixService.getVerificationSessions();
    notifyListeners();
  }

  Future<void> pickAndSendMedia({
    required MessageKind kind,
    required List<String> allowedExtensions,
  }) async {
    final roomId = _activeRoomId;
    if (roomId == null) {
      return;
    }

    if (kind == MessageKind.image) {
      final selected = await pickImagesForBatch();
      if (selected.isEmpty) {
        return;
      }
      await sendPickedImages(images: selected, caption: null);
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _errorNotifier.setError('Selected file has no readable bytes.');
      return;
    }

    await sendMedia(bytes: bytes, filename: file.name, kind: kind);
  }

  Future<List<PickedImageMedia>> pickImagesForBatchFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return const <PickedImageMedia>[];
    }

    final selected = <PickedImageMedia>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      selected.add(
        PickedImageMedia(
          bytes: bytes,
          filename: file.name.isNotEmpty ? file.name : 'image.jpg',
        ),
      );
    }
    return selected;
  }

  Future<List<PickedImageMedia>> pickImagesForBatch() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      imageQuality: 84,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked.isEmpty) {
      return const <PickedImageMedia>[];
    }

    final selected = <PickedImageMedia>[];
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      selected.add(
        PickedImageMedia(
          bytes: bytes,
          filename: file.name.isNotEmpty ? file.name : 'image.jpg',
        ),
      );
    }
    return selected;
  }

  Future<bool> sendPickedImages({
    required List<PickedImageMedia> images,
    String? caption,
  }) async {
    final roomId = _activeRoomId;
    if (roomId == null || images.isEmpty) {
      return false;
    }

    final captionText = (caption ?? '').trim();
    var sentCount = 0;
    for (var i = 0; i < images.length; i++) {
      final file = images[i];
      final captionForImage = i == 0 ? captionText : '';
      final sent = await sendMedia(
        bytes: file.bytes,
        filename: file.filename,
        kind: MessageKind.image,
        caption: captionForImage,
        refreshAfterSend: false,
      );
      if (sent) {
        sentCount++;
      }
    }

    if (sentCount == 0) {
      return false;
    }
    if (sentCount < images.length) {
      _errorNotifier.setError(
        'Uploaded $sentCount/${images.length} images. Some uploads failed.',
      );
    }

    _replyToMessage = null;

    await openRoom(roomId, roomTitle: _activeRoomTitle);
    return true;
  }

  Future<bool> pickAndSendImages({String? caption}) async {
    final selected = await pickImagesForBatch();
    if (selected.isEmpty) {
      return false;
    }
    return sendPickedImages(images: selected, caption: caption);
  }

  Future<bool> pickAndSendDocument() async {
    final roomId = _activeRoomId;
    if (roomId == null) {
      return false;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return false;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _errorNotifier.setError('Selected file has no readable bytes.');
      return false;
    }
    if (!_validateUploadSize(bytes.lengthInBytes, file.name)) {
      return false;
    }

    await _matrixService.sendMediaMessage(
      roomId: roomId,
      bytes: bytes,
      filename: file.name,
      mimeType: _mimeTypeFromFileName(file.name),
      kind: MessageKind.text,
    );
    await openRoom(roomId, roomTitle: _activeRoomTitle);
    return true;
  }

  Future<bool> sendMedia({
    required Uint8List bytes,
    required String filename,
    required MessageKind kind,
    String? caption,
    bool refreshAfterSend = true,
  }) async {
    final roomId = _activeRoomId;
    if (roomId == null) {
      return false;
    }
    if (!_validateUploadSize(bytes.lengthInBytes, filename)) {
      return false;
    }

    try {
      await _matrixService.sendMediaMessage(
        roomId: roomId,
        bytes: bytes,
        filename: filename,
        mimeType: _mimeTypeFromFileName(filename, kind),
        kind: kind,
        caption: caption,
      );
      if (refreshAfterSend) {
        await openRoom(roomId, roomTitle: _activeRoomTitle);
      }
      return true;
    } catch (e) {
      _errorNotifier.setError(e.toString());
      return false;
    }
  }

  String _mimeTypeFromFileName(String filename, [MessageKind? kind]) {
    final lower = filename.toLowerCase();
    if (kind == MessageKind.video ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi')) {
      if (lower.endsWith('.mov')) return 'video/quicktime';
      if (lower.endsWith('.avi')) return 'video/x-msvideo';
      return 'video/mp4';
    }
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _refreshFromSync() async {
    try {
      _threads = await _matrixService.getJoinedThreads();
      _verificationSessions = _matrixService.getVerificationSessions();
    } catch (e) {
      if (!_isTransientNetworkError(e)) {
        _errorNotifier.setError(e.toString());
      }
    }

    final roomId = _activeRoomId;
    if (roomId != null) {
      try {
        _messages = await _matrixService.getRoomMessages(roomId);
      } catch (e) {
        if (!_isTransientNetworkError(e)) {
          _errorNotifier.setError(e.toString());
        }
      }
      try {
        _participants = await _matrixService.getRoomParticipants(roomId);
      } catch (e) {
        if (!_isTransientNetworkError(e)) {
          _errorNotifier.setError(e.toString());
        }
      }
      try {
        _typingUsers = await _matrixService.getTypingUsers(roomId);
      } catch (e) {
        if (!_isTransientNetworkError(e)) {
          _errorNotifier.setError(e.toString());
        }
      }
      try {
        await _matrixService.setReadMarker(roomId);
      } catch (_) {
        // Read markers are best-effort.
      }
    }
    notifyListeners();
  }

  Future<void> _connectMatrixInternal({
    required String username,
    required String password,
  }) async {
    _updateMatrixSyncProgress(0.28, 'Checking chat server...');
    final reachable = await _connectivityService.isMatrixReachable();
    if (!reachable) {
      throw Exception('Matrix homeserver is not reachable');
    }

    _updateMatrixSyncProgress(0.44, 'Signing into chat server...');
    await _matrixService.loginWithPassword(
      username: username,
      password: password,
    );
    _updateMatrixSyncProgress(0.72, 'Loading conversations...');
    await _syncSubscription?.cancel();
    _syncSubscription = _matrixService.syncUpdates.listen((_) async {
      try {
        await _refreshFromSync();
      } catch (e, st) {
        if (_isTransientNetworkError(e)) {
          return;
        }
        debugPrint('sync refresh failed: $e');
        debugPrint('$st');
        _errorNotifier.setError(e.toString());
      }
    });

    await loadThreads(onProgress: _updateMatrixSyncProgress);
    _verificationSessions = _matrixService.getVerificationSessions();
    _updateMatrixSyncProgress(1, 'Chats ready');
  }

  void _setMatrixConnecting(
    bool value, {
    required double progress,
    required String status,
  }) {
    _matrixConnecting = value;
    _matrixSyncProgress = progress.clamp(0, 1).toDouble();
    _matrixSyncStatus = status;
    notifyListeners();
  }

  void _updateMatrixSyncProgress(double progress, String status) {
    final normalized = progress.clamp(0, 1).toDouble();
    if (_matrixSyncProgress == normalized && _matrixSyncStatus == status) {
      return;
    }
    _matrixSyncProgress = normalized;
    _matrixSyncStatus = status;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  String _describeError(Object error) {
    if (error is FirebaseAuthException) {
      final code = error.code.trim();
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return code.isEmpty
            ? message
            : 'Firebase auth failed ($code): $message';
      }
      return code.isEmpty
          ? 'Firebase auth failed'
          : 'Firebase auth failed ($code)';
    }

    if (error is PlatformException) {
      final code = error.code.trim();
      final message = error.message?.trim();
      final details = error.details?.toString().trim();
      final buffer = StringBuffer('Platform error');
      if (code.isNotEmpty) {
        buffer.write(' ($code)');
      }
      if (message != null && message.isNotEmpty) {
        buffer.write(': $message');
      }
      if (details != null && details.isNotEmpty) {
        buffer.write(' [$details]');
      }
      return buffer.toString();
    }

    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return 'Unknown error';
    }
    return raw.replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
  }

  bool _validateUploadSize(int sizeBytes, String filename) {
    if (sizeBytes <= _maxUploadBytes) {
      return true;
    }
    final sizeMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    _errorNotifier.setError(
      '"$filename" is $sizeMb MB. Max upload size is 10 MB.',
    );
    return false;
  }

  bool _isTransientNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('clientexception with socketexception');
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}

class PickedImageMedia {
  const PickedImageMedia({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}
