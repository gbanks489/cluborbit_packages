import 'dart:async';

import 'package:image/image.dart' as img;
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cluborbit_models/cluborbit_models.dart';
import 'package:clubcommon/clubcommon.dart';

import '../services/auth_service.dart';
import '../services/chat_thread_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    unawaited(_hydrateThreadPreferences());
  }

  final AuthService _authService;
  final MatrixRestService _matrixService;
  final ConnectivityService _connectivityService;
  final ErrorNotifier _errorNotifier;
  final UserProfileService _userProfileService;
  final IncomingCallSettingsStore _incomingCallSettingsStore;
  final ChatThreadPreferencesStore _threadPreferencesStore =
      ChatThreadPreferencesStore();

  StreamSubscription<void>? _syncSubscription;
  bool _isDisposed = false;

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
  final Map<String, Set<String>> _deletedForMeMessageIdsByRoom =
      <String, Set<String>>{};
  final Map<String, int> _pendingPushUnreadCounts = <String, int>{};
  final Map<String, Set<String>> _pendingPushEventIdsByRoom =
      <String, Set<String>>{};
  Set<String> _mutedRoomIds = const <String>{};
  Set<String> _pinnedRoomIds = const <String>{};
  Set<String> _forcedUnreadRoomIds = const <String>{};
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
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _threads
        : _threads
              .where(
                (thread) =>
                    thread.title.toLowerCase().contains(query) ||
                    (thread.lastMessage ?? '').toLowerCase().contains(query),
              )
              .toList(growable: false);

    final withLocalPrefs = filtered
        .map(_applyThreadPreferences)
        .toList(growable: false);
    final indexed = withLocalPrefs.indexed.toList(growable: false)
      ..sort((a, b) {
        final aPinned = _pinnedRoomIds.contains(a.$2.id);
        final bPinned = _pinnedRoomIds.contains(b.$2.id);
        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }
        return a.$1.compareTo(b.$1);
      });
    return indexed.map((entry) => entry.$2).toList(growable: false);
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

  Future<void> _hydrateThreadPreferences() async {
    try {
      final snapshot = await _threadPreferencesStore.loadAll();
      _mutedRoomIds = Set<String>.from(snapshot.mutedRoomIds);
      _pinnedRoomIds = Set<String>.from(snapshot.pinnedRoomIds);
      _forcedUnreadRoomIds = Set<String>.from(snapshot.forcedUnreadRoomIds);
      notifyListeners();
    } catch (e, s) {
      debugPrint('Failed to load chat thread preferences: $e\n$s');
    }
  }

  ChatThread _applyThreadPreferences(ChatThread thread) {
    final resolvedUnreadCount = _resolveUnreadCount(thread);
    if (resolvedUnreadCount != thread.unreadCount) {
      return thread.copyWith(unreadCount: resolvedUnreadCount);
    }
    return thread;
  }

  int _resolveUnreadCount(ChatThread thread) {
    var unreadCount = thread.unreadCount;
    final pendingPushUnreadCount = _pendingPushUnreadCounts[thread.id];
    if (pendingPushUnreadCount != null &&
        pendingPushUnreadCount > unreadCount) {
      unreadCount = pendingPushUnreadCount;
    }
    if (_forcedUnreadRoomIds.contains(thread.id) && unreadCount == 0) {
      unreadCount = 1;
    }
    return unreadCount;
  }

  void _recordPendingPushUnread(String roomId, {String? eventId}) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }

    final normalizedEventId = eventId?.trim();
    if (normalizedEventId != null && normalizedEventId.isNotEmpty) {
      final knownEventIds = _pendingPushEventIdsByRoom.putIfAbsent(
        normalizedRoomId,
        () => <String>{},
      );
      if (!knownEventIds.add(normalizedEventId)) {
        return;
      }
    }

    // Only count pushes that haven't been confirmed by a sync yet.
    // _resolveUnreadCount already returns max(synapse_count, pending_count),
    // so stacking on top of the Synapse count would double-count the message
    // (e.g. Synapse says 1, push adds 1 → shows 2 for a single message).
    final existingPending = _pendingPushUnreadCounts[normalizedRoomId] ?? 0;
    final nextUnreadCount = existingPending + 1;
    _pendingPushUnreadCounts[normalizedRoomId] = nextUnreadCount;
  }

  void _clearPendingPushUnread(String roomId) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }
    _pendingPushUnreadCounts.remove(normalizedRoomId);
    _pendingPushEventIdsByRoom.remove(normalizedRoomId);
  }

  void _reconcilePendingPushUnreadCounts() {
    if (_pendingPushUnreadCounts.isEmpty) {
      return;
    }

    final resolvedServerUnreadByRoom = <String, int>{
      for (final thread in _threads) thread.id: thread.unreadCount,
    };

    final roomsToClear = <String>[];
    _pendingPushUnreadCounts.forEach((roomId, pendingUnreadCount) {
      final serverUnreadCount = resolvedServerUnreadByRoom[roomId];
      if (serverUnreadCount != null &&
          serverUnreadCount >= pendingUnreadCount) {
        roomsToClear.add(roomId);
      }
    });

    for (final roomId in roomsToClear) {
      _clearPendingPushUnread(roomId);
    }
  }

  void _clearActiveRoomUnreadState(String roomId) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }

    _clearPendingPushUnread(normalizedRoomId);
    _threads = _threads
        .map(
          (thread) => thread.id == normalizedRoomId
              ? thread.copyWith(unreadCount: 0)
              : thread,
        )
        .toList(growable: false);
    if (_forcedUnreadRoomIds.remove(normalizedRoomId)) {
      unawaited(
        _threadPreferencesStore.setForcedUnread(normalizedRoomId, false),
      );
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

  /// Disconnects the Matrix session and clears all local chat state, without
  /// signing out of Firebase. Use this when the Firebase user has already
  /// changed and you need to reset Matrix before connecting as the new user.
  Future<void> disconnectMatrix() async {
    try {
      await _syncSubscription?.cancel();
      _syncSubscription = null;
      _lastBackgroundConnectAttemptUid = null;
      _setMatrixConnecting(false, progress: 0, status: 'Preparing chats...');
      await _matrixService.logout();
      unawaited(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('homeserver_url');
          await prefs.remove('access_token');
        } catch (_) {}
      }());

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
    } catch (_) {
      // Best-effort teardown — do not rethrow.
    } finally {
      notifyListeners();
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
    _messages = const <ChatMessage>[];
    _participants = const <ChatParticipant>[];
    _typingUsers = const <ChatParticipant>[];
    _verificationSessions = const <VerificationSession>[];
    _activeRoomEncryptionStatus = const ChatEncryptionStatus.unencrypted();
    _replyToMessage = null;
    _setLoading(true);
    notifyListeners();
    try {
      _messages = _applyDeleteForMeFilter(
        roomId,
        await _matrixService.getRoomMessages(roomId),
      );
      await _matrixService.setReadMarker(roomId);
      _clearActiveRoomUnreadState(roomId);
      _participants = await _matrixService.getRoomParticipants(roomId);
      _typingUsers = await _matrixService.getTypingUsers(roomId);
      _activeRoomEncryptionStatus = await _matrixService
          .getRoomEncryptionStatus(roomId);
      _verificationSessions = _matrixService.getVerificationSessions();
      _errorNotifier.clear();
    } catch (e) {
      // Don't call setError here — openRoom always rethrows so the caller
      // (openRoomInBackground or a direct await site) is responsible for
      // deciding whether/how to surface the error. Reporting here would cause
      // double-notifications when called via openRoomInBackground.
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  void openRoomInBackground(String roomId, {String? roomTitle}) {
    unawaited(
      openRoom(roomId, roomTitle: roomTitle).catchError((Object error) {
        // Membership timing errors (M_FORBIDDEN) during invite→join transitions
        // are expected and should not be shown to the user.
        if (!_isMembershipError(error)) {
          _errorNotifier.setError(error.toString());
        }
      }),
    );
  }

  void clearActiveRoom({String? roomId}) {
    final normalizedRoomId = roomId?.trim();
    if (normalizedRoomId != null &&
        normalizedRoomId.isNotEmpty &&
        _activeRoomId != normalizedRoomId) {
      return;
    }
    if (_activeRoomId == null &&
        _activeRoomTitle == null &&
        _messages.isEmpty &&
        _participants.isEmpty &&
        _typingUsers.isEmpty &&
        _verificationSessions.isEmpty) {
      return;
    }

    _activeRoomId = null;
    _activeRoomTitle = null;
    _messages = const <ChatMessage>[];
    _participants = const <ChatParticipant>[];
    _typingUsers = const <ChatParticipant>[];
    _verificationSessions = const <VerificationSession>[];
    _activeRoomEncryptionStatus = const ChatEncryptionStatus.unencrypted();
    _replyToMessage = null;
    notifyListeners();
  }

  Future<bool> joinRoomIfInvited(String roomId) {
    return _matrixService.joinRoomIfInvited(roomId);
  }

  Future<String> resolveRoomForNavigation(String roomIdOrAlias) async {
    final normalized = Uri.decodeComponent(roomIdOrAlias).trim();
    if (normalized.isEmpty) {
      return normalized;
    }

    for (final thread in _threads) {
      if (thread.id == normalized ||
          Uri.encodeComponent(thread.id) == roomIdOrAlias) {
        return thread.id;
      }
    }

    try {
      return await _matrixService.resolveRoomId(normalized);
    } catch (error) {
      debugPrint(
        '[ChatController.resolveRoomForNavigation] fallback to raw identifier=$normalized error=$error',
      );
      return normalized;
    }
  }

  /// Runs a full background integrity check across all cached threads.
  /// Performs a full-state sync then repairs every room that has incomplete or
  /// stale data (missing title, last-message, or avatar).  Any rooms that were
  /// entirely missing from the local cache are added.
  ///
  /// [onProgress] receives values in [0, 1] with a human-readable status.
  /// Returns the number of threads repaired or newly discovered.
  Future<int> runIntegrityCheck({
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      final count = await _matrixService.runFullIntegrityCheck(
        onProgress: onProgress,
      );
      await _refreshFromSync();
      notifyListeners();
      return count;
    } catch (e) {
      if (!_isTransientNetworkError(e)) {
        _errorNotifier.setError(e.toString());
      }
      return 0;
    }
  }

  Future<void> refreshChatDetails() async {
    final roomId = _activeRoomId;
    if (roomId == null) {
      return;
    }
    try {
      _participants = await _matrixService.getRoomParticipants(roomId);
    } catch (error) {
      debugPrint(
        '[ChatController.refreshChatDetails] participants error=$error',
      );
      _errorNotifier.setError(error.toString());
      _participants = const <ChatParticipant>[];
    }

    try {
      _activeRoomEncryptionStatus = await _matrixService
          .getRoomEncryptionStatus(roomId);
    } catch (error) {
      debugPrint('[ChatController.refreshChatDetails] encryption error=$error');
      _errorNotifier.setError(error.toString());
      _activeRoomEncryptionStatus = const ChatEncryptionStatus.unencrypted();
    }

    _verificationSessions = _matrixService.getVerificationSessions();
    notifyListeners();
  }

  Future<void> refreshFromPush({String? roomId, String? eventId}) async {
    if (!hasFirebaseSession) {
      return;
    }
    final normalizedRoomId = roomId?.trim();
    if (normalizedRoomId != null &&
        normalizedRoomId.isNotEmpty &&
        normalizedRoomId != _activeRoomId) {
      _recordPendingPushUnread(normalizedRoomId, eventId: eventId);
      notifyListeners();
    }
    if (matrixUserId.isEmpty) {
      await connectMatrixUsingProfileInBackground();
      return;
    }

    await _refreshFromSync();

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
    if (roomId == null) {
      _errorNotifier.setError('No active chat room — please re-open the chat.');
      return;
    }
    if (text.trim().isEmpty) {
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
    } catch (e, s) {
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
      debugPrint('[ChatController] sendOptimisticTextMessage failed: $e\n$s');
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
    // Check for an existing DM room with this user before creating a new one.
    final normalizedUserId = userId.trim();
    ChatThread? invitedThread;
    for (final thread in _threads) {
      if (thread.type != ChatType.dm) continue;
      final counterpart = _matrixService.cachedDirectMessageCounterpart(
        thread.id,
      );
      if (counterpart != null && counterpart.userId == normalizedUserId) {
        if (thread.isInvited) {
          // Keep track of the invite so we can accept it below.
          invitedThread = thread;
          continue;
        }
        // Already a joined member — open the existing room directly.
        _activeRoomId = thread.id;
        _activeRoomTitle = roomTitle ?? thread.title;
        notifyListeners();
        openRoomInBackground(thread.id, roomTitle: _activeRoomTitle);
        return thread.id;
      }
    }

    // If we found an invite, accept it instead of creating a new room.
    if (invitedThread != null) {
      final joined = await _matrixService.joinRoomIfInvited(invitedThread.id);
      if (joined) {
        _activeRoomId = invitedThread.id;
        _activeRoomTitle = roomTitle ?? invitedThread.title;
        _messages = const <ChatMessage>[];
        _participants = const <ChatParticipant>[];
        _typingUsers = const <ChatParticipant>[];
        _verificationSessions = const <VerificationSession>[];
        _activeRoomEncryptionStatus = const ChatEncryptionStatus.unencrypted();
        notifyListeners();
        unawaited(loadThreads());
        openRoomInBackground(invitedThread.id, roomTitle: _activeRoomTitle);
        return invitedThread.id;
      }
      // If the join failed fall through and create a fresh room.
    }

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

  Future<ChatUserPresence> getUserPresence(
    String userId, {
    bool forceRefresh = false,
  }) {
    return _matrixService.getUserPresence(userId, forceRefresh: forceRefresh);
  }

  ChatUserPresence? cachedUserPresence(String userId) {
    return _matrixService.cachedUserPresence(userId);
  }

  ChatParticipant? cachedDirectMessageCounterpart(String roomId) {
    return _matrixService.cachedDirectMessageCounterpart(roomId);
  }

  bool isRoomMuted(String roomId) {
    return _mutedRoomIds.contains(roomId);
  }

  bool isRoomPinned(String roomId) {
    return _pinnedRoomIds.contains(roomId);
  }

  bool hasForcedUnreadMark(String roomId) {
    return _forcedUnreadRoomIds.contains(roomId);
  }

  Future<void> setRoomMuted(String roomId, bool muted) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }

    final next = Set<String>.from(_mutedRoomIds);
    if (muted) {
      next.add(normalizedRoomId);
    } else {
      next.remove(normalizedRoomId);
    }
    _mutedRoomIds = next;
    notifyListeners();

    try {
      await _threadPreferencesStore.setMuted(normalizedRoomId, muted);
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    }
  }

  Future<void> setRoomPinned(String roomId, bool pinned) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }

    final next = Set<String>.from(_pinnedRoomIds);
    if (pinned) {
      next.add(normalizedRoomId);
    } else {
      next.remove(normalizedRoomId);
    }
    _pinnedRoomIds = next;
    notifyListeners();

    try {
      await _threadPreferencesStore.setPinned(normalizedRoomId, pinned);
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    }
  }

  Future<void> markRoomAsUnread(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }
    if (_forcedUnreadRoomIds.contains(normalizedRoomId)) {
      return;
    }

    _forcedUnreadRoomIds = Set<String>.from(_forcedUnreadRoomIds)
      ..add(normalizedRoomId);
    notifyListeners();

    try {
      await _threadPreferencesStore.setForcedUnread(normalizedRoomId, true);
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    }
  }

  Future<void> clearRoomUnreadMark(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }

    _clearPendingPushUnread(normalizedRoomId);
    if (_forcedUnreadRoomIds.remove(normalizedRoomId)) {
      notifyListeners();
      try {
        await _threadPreferencesStore.setForcedUnread(normalizedRoomId, false);
      } catch (e) {
        _errorNotifier.setError(e.toString());
        rethrow;
      }
    }
  }

  Future<void> leaveRoom(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }

    _setLoading(true);
    try {
      await _matrixService.leaveRoom(normalizedRoomId);
      _mutedRoomIds = Set<String>.from(_mutedRoomIds)..remove(normalizedRoomId);
      _pinnedRoomIds = Set<String>.from(_pinnedRoomIds)
        ..remove(normalizedRoomId);
      _clearPendingPushUnread(normalizedRoomId);
      _forcedUnreadRoomIds = Set<String>.from(_forcedUnreadRoomIds)
        ..remove(normalizedRoomId);
      await _threadPreferencesStore.removeRoom(normalizedRoomId);

      if (_activeRoomId == normalizedRoomId) {
        _activeRoomId = null;
        _activeRoomTitle = null;
        _messages = const <ChatMessage>[];
        _participants = const <ChatParticipant>[];
        _typingUsers = const <ChatParticipant>[];
        _verificationSessions = const <VerificationSession>[];
        _activeRoomEncryptionStatus = const ChatEncryptionStatus.unencrypted();
      }

      await loadThreads();
      _errorNotifier.clear();
    } catch (e) {
      _errorNotifier.setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
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

  bool _isForbiddenRedactionError(Object error) {
    final message = error.toString().toUpperCase();
    return message.contains('M_FORBIDDEN') ||
        message.contains('HTTP 403') ||
        message.contains('FORBIDDEN');
  }

  bool _isRateLimitedError(Object error) {
    final message = error.toString().toUpperCase();
    return message.contains('M_LIMIT_EXCEEDED') ||
        message.contains('TOO MANY REQUESTS');
  }

  bool _isNotFoundRedactionError(Object error) {
    final message = error.toString().toUpperCase();
    return message.contains('M_NOT_FOUND') || message.contains('HTTP 404');
  }

  void _logDeleteFailure({
    required String roomId,
    required Set<String> eventIds,
    required Object error,
    StackTrace? stackTrace,
  }) {
    debugPrint(
      '[ChatController.deleteMessages] roomId=$roomId eventIds=${eventIds.join(',')} errorType=${error.runtimeType}',
    );
    debugPrint('[ChatController.deleteMessages] error=$error');
    if (stackTrace != null) {
      debugPrint('[ChatController.deleteMessages] stack=$stackTrace');
    }
  }

  List<ChatMessage> _applyDeleteForMeFilter(
    String roomId,
    List<ChatMessage> messages,
  ) {
    final hiddenIds = _deletedForMeMessageIdsByRoom[roomId];
    if (hiddenIds == null || hiddenIds.isEmpty) {
      return messages;
    }
    return messages
        .where((message) => !hiddenIds.contains(message.id))
        .toList(growable: false);
  }

  Future<void> deleteMessagesForMe(List<String> eventIds) async {
    final roomId = _activeRoomId;
    if (roomId == null || eventIds.isEmpty) return;
    final hiddenIds = _deletedForMeMessageIdsByRoom.putIfAbsent(
      roomId,
      () => <String>{},
    );
    hiddenIds.addAll(eventIds.where((eventId) => eventId.isNotEmpty));

    final previousReplyTo = _replyToMessage;
    _messages = _applyDeleteForMeFilter(roomId, _messages);
    if (previousReplyTo != null && hiddenIds.contains(previousReplyTo.id)) {
      _replyToMessage = null;
    }
    notifyListeners();
  }

  Future<void> deleteMessages(List<String> eventIds) async {
    final roomId = _activeRoomId;
    if (roomId == null || eventIds.isEmpty) return;
    final uniqueEventIds = eventIds
        .where((eventId) => eventId.isNotEmpty)
        .toSet();
    if (uniqueEventIds.isEmpty) {
      return;
    }
    final remoteEventIds = uniqueEventIds
        .where((eventId) => !eventId.startsWith('local:'))
        .toList(growable: false);
    final localOnlyEventIds = uniqueEventIds
        .where((eventId) => eventId.startsWith('local:'))
        .toList(growable: false);
    final previousMessages = _messages;
    final previousReplyTo = _replyToMessage;

    _messages = _messages
        .where((message) => !uniqueEventIds.contains(message.id))
        .toList(growable: false);
    if (previousReplyTo != null &&
        uniqueEventIds.contains(previousReplyTo.id)) {
      _replyToMessage = null;
    }
    notifyListeners();

    try {
      for (final eventId in remoteEventIds) {
        await _matrixService.redactEvent(roomId: roomId, eventId: eventId);
      }
      _messages = _applyDeleteForMeFilter(
        roomId,
        await _matrixService.getRoomMessages(roomId, allowCache: false),
      );
      if (localOnlyEventIds.isNotEmpty) {
        _messages = _messages
            .where((message) => !uniqueEventIds.contains(message.id))
            .toList(growable: false);
      }
      notifyListeners();
    } catch (error, stackTrace) {
      _logDeleteFailure(
        roomId: roomId,
        eventIds: uniqueEventIds,
        error: error,
        stackTrace: stackTrace,
      );
      if (_isForbiddenRedactionError(error) ||
          _isRateLimitedError(error) ||
          _isNotFoundRedactionError(error)) {
        await deleteMessagesForMe(uniqueEventIds.toList(growable: false));
        final upper = error.toString().toUpperCase();
        if (upper.contains('M_LIMIT_EXCEEDED') ||
            upper.contains('TOO MANY REQUESTS')) {
          _errorNotifier.setError(
            'Delete for everyone is rate-limited right now. Removed locally instead.',
          );
        } else if (upper.contains('M_NOT_FOUND') ||
            upper.contains('HTTP 404')) {
          _errorNotifier.setError(
            'Message was already removed on server. Hidden locally.',
          );
        } else {
          _errorNotifier.setError(
            'Could not delete for everyone. Removed locally instead.',
          );
        }
        return;
      }
      _messages = previousMessages;
      _replyToMessage = previousReplyTo;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteMessage(String eventId) async {
    await deleteMessages(<String>[eventId]);
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

  /// Removes the user's own reaction by redacting its event. [reactionEventId]
  /// is the event ID of the `m.reaction` event to redact.
  Future<void> removeReaction(String reactionEventId) async {
    final roomId = _activeRoomId;
    if (roomId == null) return;
    await _matrixService.redactEvent(roomId: roomId, eventId: reactionEventId);
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

    try {
      await openRoom(roomId, roomTitle: _activeRoomTitle);
    } catch (e) {
      // Images were successfully sent; room refresh is best-effort.
      if (!_isTransientNetworkError(e)) {
        _errorNotifier.setError(e.toString());
      }
      notifyListeners();
    }
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
      _errorNotifier.setError('No active chat room — please re-open the chat.');
      return false;
    }
    if (!_validateUploadSize(bytes.lengthInBytes, filename)) {
      return false;
    }

    try {
      final uploadBytes = kind == MessageKind.image
          ? await _compressImageIfNeeded(bytes, filename)
          : bytes;
      await _matrixService.sendMediaMessage(
        roomId: roomId,
        bytes: uploadBytes,
        filename: filename,
        mimeType: _mimeTypeFromFileName(filename, kind),
        kind: kind,
        caption: caption,
      );
      if (refreshAfterSend) {
        await openRoom(roomId, roomTitle: _activeRoomTitle);
      }
      return true;
    } catch (e, s) {
      debugPrint('[ChatController] sendMedia failed: $e\n$s');
      _errorNotifier.setError(e.toString());
      return false;
    }
  }

  /// Compresses an image to ensure it fits within [maxBytes].
  /// Decodes the image, scales it down if wider/taller than [maxDimension],
  /// then re-encodes as JPEG reducing quality until small enough.
  /// Returns the original bytes unchanged if not an image or already small.
  Future<Uint8List> _compressImageIfNeeded(
    Uint8List bytes,
    String filename, {
    int maxBytes = 4 * 1024 * 1024, // 4 MB
    int maxDimension = 1920,
  }) async {
    if (bytes.lengthInBytes <= maxBytes) {
      return bytes;
    }
    final lower = filename.toLowerCase();
    final isImage =
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp');
    if (!isImage) {
      return bytes;
    }

    return compute(
      _compressImageBytesIsolate,
      _CompressArgs(
        bytes: bytes,
        maxBytes: maxBytes,
        maxDimension: maxDimension,
      ),
    );
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
      // Use the service's in-memory cache which is already kept current by
      // _applyThreadSyncDelta in the long-poll loop. Calling getJoinedThreads()
      // here would fire an extra /sync?timeout=0, which can return rooms with
      // unread_notifications absent or zero and silently wipe badge counts.
      final cached = _matrixService.cachedThreads;
      _threads = cached.isNotEmpty
          ? cached
          : await _matrixService.getJoinedThreads();
      _reconcilePendingPushUnreadCounts();
      final activeRoomId = _activeRoomId;
      if (activeRoomId != null && activeRoomId.trim().isNotEmpty) {
        _clearActiveRoomUnreadState(activeRoomId);
      }
      _verificationSessions = _matrixService.getVerificationSessions();
      _clearTransientNetworkErrorBanner();
    } catch (e) {
      if (!_isTransientNetworkError(e)) {
        _errorNotifier.setError(e.toString());
      }
    }

    final roomId = _activeRoomId;
    if (roomId != null) {
      try {
        // Always bypass the cache for the active room so new messages that
        // arrived in this sync cycle are shown immediately rather than waiting
        // for the 8-second background-refresh cooldown to expire.
        _messages = _applyDeleteForMeFilter(
          roomId,
          await _matrixService.getRoomMessages(roomId, allowCache: false),
        );
      } catch (e) {
        // Membership errors (M_FORBIDDEN) are silently ignored here: the user
        // may still be transitioning from an invite to a joined state, and the
        // periodic sync should not spam the error banner for this.
        if (!_isTransientNetworkError(e) && !_isMembershipError(e)) {
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
    final matrixCreds = await _matrixService.loginWithPassword(
      username: username,
      password: password,
    );
    // Persist credentials so the main isolate can show notifications when
    // the app is backgrounded (background-isolate MethodChannels are unreliable
    // when the main isolate is alive).
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('homeserver_url', _matrixService.homeserver);
        await prefs.setString('access_token', matrixCreds.accessToken);
      } catch (_) {}
    }());
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
        text.contains('connection closed before full header was received') ||
        text.contains('connection closed before full header') ||
        text.contains('clientexception: connection closed') ||
        text.contains('socketexception') ||
        text.contains('clientexception with socketexception');
  }

  /// Returns true for Matrix membership errors (M_FORBIDDEN, M_UNKNOWN_TOKEN)
  /// that indicate the current user is not (yet) a member of the room.
  /// These are timing-related during invite→join transitions and should not
  /// be surfaced to the user or retried indefinitely.
  bool _isMembershipError(Object error) {
    final text = error.toString();
    return text.contains('M_FORBIDDEN') || text.contains('M_UNKNOWN_TOKEN');
  }

  void _clearTransientNetworkErrorBanner() {
    final errorMessage = _errorNotifier.errorMessage;
    if (errorMessage == null || errorMessage.trim().isEmpty) {
      return;
    }
    if (_isTransientNetworkError(errorMessage)) {
      _errorNotifier.clear();
    }
  }

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _syncSubscription?.cancel();
    super.dispose();
  }
}

class PickedImageMedia {
  const PickedImageMedia({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

// ---------------------------------------------------------------------------
// Image compression helpers (run in an isolate via compute())
// ---------------------------------------------------------------------------

class _CompressArgs {
  const _CompressArgs({
    required this.bytes,
    required this.maxBytes,
    required this.maxDimension,
  });
  final Uint8List bytes;
  final int maxBytes;
  final int maxDimension;
}

Uint8List _compressImageBytesIsolate(_CompressArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) {
    return args.bytes;
  }

  // Scale down if either dimension exceeds maxDimension.
  img.Image resized = decoded;
  if (decoded.width > args.maxDimension || decoded.height > args.maxDimension) {
    resized = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? args.maxDimension : -1,
      height: decoded.height >= decoded.width ? args.maxDimension : -1,
    );
  }

  // Try progressively lower quality until we fit.
  for (final quality in [82, 70, 55, 40]) {
    final encoded = img.encodeJpg(resized, quality: quality);
    if (encoded.length <= args.maxBytes) {
      return Uint8List.fromList(encoded);
    }
  }
  // Last resort: encode at minimum quality.
  return Uint8List.fromList(img.encodeJpg(resized, quality: 25));
}
