import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cluborbit_models/cluborbit_models.dart';

import '../config/playerchat_config.dart';
import '../matrix_core/matrix_rust_crypto_transport_client.dart';
import '../matrix_core/matrix_transport_client.dart';
import 'matrix_rest_cache_store.dart';

class MatrixCredentials {
  const MatrixCredentials({
    required this.userId,
    required this.accessToken,
    this.deviceId,
  });

  final String userId;
  final String accessToken;
  final String? deviceId;
}

class MatrixTurnServerInfo {
  const MatrixTurnServerInfo({
    required this.uris,
    required this.username,
    required this.password,
    required this.ttl,
  });

  final List<String> uris;
  final String username;
  final String password;
  final int ttl;

  bool get isUsable {
    return uris.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
  }
}

enum ChatCallPhase {
  idle,
  ringing,
  connecting,
  connected,
  ending,
  ended,
  error,
}

class ChatCallSnapshot {
  const ChatCallSnapshot({
    required this.phase,
    required this.isVideo,
    required this.isIncoming,
    required this.microphoneMuted,
    required this.videoMuted,
    required this.speakerOn,
    this.remoteUserId,
    this.remoteDisplayName,
    this.remoteAvatarUrl,
    this.error,
  });

  const ChatCallSnapshot.idle()
    : phase = ChatCallPhase.idle,
      isVideo = false,
      isIncoming = false,
      microphoneMuted = false,
      videoMuted = false,
      speakerOn = false,
      remoteUserId = null,
      remoteDisplayName = null,
      remoteAvatarUrl = null,
      error = null;

  final ChatCallPhase phase;
  final bool isVideo;
  final bool isIncoming;
  final bool microphoneMuted;
  final bool videoMuted;
  final bool speakerOn;
  final String? remoteUserId;
  final String? remoteDisplayName;
  final String? remoteAvatarUrl;
  final String? error;

  bool get hasLiveCall {
    return phase != ChatCallPhase.idle && phase != ChatCallPhase.ended;
  }
}

class _QueuedIncomingCall {
  const _QueuedIncomingCall({
    required this.roomId,
    required this.callId,
    required this.offerSdp,
    required this.isVideo,
    required this.senderId,
    required this.senderDisplayName,
  });

  final String roomId;
  final String callId;
  final String offerSdp;
  final bool isVideo;
  final String senderId;
  final String? senderDisplayName;
}

class MatrixRestService {
  static const Duration _syncRetryDelay = Duration(seconds: 2);
  static const int _syncLongPollTimeoutMs = 30000;
  static const String _localMessagePrefix = 'local:';

  MatrixRestService({
    required String homeserver,
    this.clientName = 'cluborbit_chat_client',
    this.databaseName = 'cluborbit_chat_matrix_sdk',
    this.databaseBuilder,
    this.transportFactory,
  }) : _homeserver = homeserver.endsWith('/')
           ? homeserver.substring(0, homeserver.length - 1)
           : homeserver,
       _core =
           transportFactory?.call(
             homeserver: homeserver.endsWith('/')
                 ? homeserver.substring(0, homeserver.length - 1)
                 : homeserver,
             clientName: clientName,
           ) ??
           MatrixRustCryptoTransportClient(
             homeserver: homeserver.endsWith('/')
                 ? homeserver.substring(0, homeserver.length - 1)
                 : homeserver,
             clientName: clientName,
           );

  final String _homeserver;
  final String clientName;
  final String databaseName;

  /// The Matrix homeserver this service is connected to.
  String get homeserver => _homeserver;
  final MatrixDatabaseBuilder? databaseBuilder;
  final MatrixTransportFactory? transportFactory;

  static const String _forwardedPrefix = '[Forwarded]\n';

  final StreamController<void> _syncUpdates =
      StreamController<void>.broadcast();
  final StreamController<ChatCallSnapshot> _callUpdates =
      StreamController<ChatCallSnapshot>.broadcast();
  final StreamController<void> _callMediaUpdates =
      StreamController<void>.broadcast();

  final MatrixTransportClient _core;
  bool _initialized = false;
  int _syncLoopGeneration = 0;

  final Map<String, Set<String>> _typingUsersByRoom = <String, Set<String>>{};
  final Map<String, Map<String, Set<String>>> _readReceiptsByRoomEvent =
      <String, Map<String, Set<String>>>{};
  final Map<String, List<ChatParticipant>> _participantsCache =
      <String, List<ChatParticipant>>{};
  final Map<String, DateTime> _participantsCacheAt = <String, DateTime>{};
  final Map<String, List<ChatParticipant>> _userSearchCache =
      <String, List<ChatParticipant>>{};
  final Map<String, ChatUserPresence> _presenceCache =
      <String, ChatUserPresence>{};
  final Map<String, DateTime> _presenceCacheAt = <String, DateTime>{};
  final Map<String, String> _lastMessagePreviewByRoom = <String, String>{};
  final Map<String, String> _lastMessageSenderByRoom = <String, String>{};
  final Map<String, String> _lastMessageSenderIdByRoom = <String, String>{};
  final Map<String, DateTime> _lastMessageTimeByRoom = <String, DateTime>{};
  final Set<String> _seenCallEventIds = <String>{};
  final List<_QueuedIncomingCall> _incomingCallQueue = <_QueuedIncomingCall>[];
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  final Set<String> _threadIntegrityRepairInFlight = <String>{};

  static const Duration _incomingRingTimeout = Duration(seconds: 45);
  static const Duration _outgoingRingTimeout = Duration(seconds: 45);
  static const Duration _connectingTimeout = Duration(seconds: 30);
  static const int _maxQueuedIncomingCalls = 5;

  String? _activeCallId;
  String? _activeCallRoomId;
  bool _activeCallIsVideo = false;
  bool _activeCallIsIncoming = false;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RTCVideoRenderer? _localVideoRenderer;
  RTCVideoRenderer? _remoteVideoRenderer;
  Timer? _incomingRingTimer;
  Timer? _outgoingRingTimer;
  Timer? _connectingTimer;

  String? _incomingCallId;
  String? _incomingCallRoomId;
  String? _incomingOfferSdp;
  String? _incomingCallerUserId;
  String? _incomingCallerDisplayName;

  static const Duration _participantsCacheTtl = Duration(seconds: 30);

  ChatCallSnapshot _callSnapshot = const ChatCallSnapshot.idle();
  static const int _perfLogThresholdMs = 200;
  static const bool _verbosePerfLogging = false;
  final MatrixRestCacheStore _cacheStore = MatrixRestCacheStore();
  List<ChatThread> _cachedThreads = const <ChatThread>[];
  // Tracks the most recent unread_notifications count received from Synapse for
  // each room via the sync loop. Only updated when Synapse explicitly sends the
  // field — never reset to 0 speculatively. Used to override stale cached counts.
  final Map<String, int> _syncedUnreadByRoom = <String, int>{};
  final Map<String, List<ChatMessage>> _cachedMessagesByRoom =
      <String, List<ChatMessage>>{};
  final Set<String> _roomMessageRefreshInFlight = <String>{};
  final Map<String, DateTime> _roomMessageRefreshAt = <String, DateTime>{};
  String? _cachedUserId;
  bool _didServeCachedThreads = false;
  static const int _maxCachedReceiptEventsPerRoom = 300;
  static const Duration _roomMessageRefreshCooldown = Duration(seconds: 8);

  void _perfLog(
    String operation,
    Stopwatch stopwatch, [
    Map<String, Object?> details = const <String, Object?>{},
    bool force = false,
  ]) {
    if (!kDebugMode) return;
    if (!_verbosePerfLogging) {
      return;
    }
    if (!force && stopwatch.elapsedMilliseconds < _perfLogThresholdMs) {
      return;
    }
    final extras = details.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    final suffix = extras.isEmpty ? '' : ' $extras';
    debugPrint(
      '[MatrixPerf] op=$operation elapsedMs=${stopwatch.elapsedMilliseconds}$suffix',
    );
  }

  Stream<void> get syncUpdates => _syncUpdates.stream;

  /// Returns the in-memory thread cache as updated by the sync loop.
  /// Use this instead of [getJoinedThreads] when you only need the latest
  /// known state without triggering an extra /sync round-trip.
  /// Unread counts are overlaid from the live sync-received values so that
  /// counts Synapse explicitly sent are never lost to a stale cache read.
  List<ChatThread> get cachedThreads {
    if (_syncedUnreadByRoom.isEmpty) {
      return List<ChatThread>.from(_cachedThreads);
    }
    return _cachedThreads
        .map((t) {
          final synced = _syncedUnreadByRoom[t.id];
          if (synced != null && synced != t.unreadCount) {
            return t.copyWith(unreadCount: synced);
          }
          return t;
        })
        .toList(growable: false);
  }

  Stream<ChatCallSnapshot> get callUpdates => _callUpdates.stream;
  Stream<void> get callMediaUpdates => _callMediaUpdates.stream;
  ChatCallSnapshot get callSnapshot => _callSnapshot;
  RTCVideoRenderer? get localVideoRenderer => _localVideoRenderer;
  RTCVideoRenderer? get remoteVideoRenderer => _remoteVideoRenderer;
  MatrixTransportCapabilities get transportCapabilities => _core.capabilities;
  String? cachedRoomAvatarUrl(String roomId) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return null;
    }
    for (final thread in _cachedThreads) {
      if (thread.id == normalizedRoomId) {
        final avatarUrl = thread.avatarUrl?.trim();
        return (avatarUrl == null || avatarUrl.isEmpty) ? null : avatarUrl;
      }
    }
    return null;
  }

  String? cachedParticipantAvatarUrl(String roomId, String userId) {
    final normalizedRoomId = roomId.trim();
    final normalizedUserId = userId.trim();
    if (normalizedRoomId.isEmpty || normalizedUserId.isEmpty) {
      return null;
    }

    final participants = _participantsCache[normalizedRoomId];
    if (participants == null) {
      return null;
    }

    for (final participant in participants) {
      if (participant.userId == normalizedUserId) {
        final avatarUrl = participant.avatarUrl?.trim();
        return (avatarUrl == null || avatarUrl.isEmpty) ? null : avatarUrl;
      }
    }
    return null;
  }

  bool get isLoggedIn => _initialized && _core.isLoggedIn;
  String? get currentUserId => _initialized ? _core.currentUserId : null;

  Future<void> initialize() async {
    if (_initialized) return;
    await _ensureVideoRenderers();
    _initialized = true;
  }

  Future<MatrixCredentials> loginWithPassword({
    required String username,
    required String password,
  }) async {
    await initialize();

    final result = await _core.loginPassword(
      username: username,
      password: password,
      initialDeviceDisplayName: 'ClubOrbit Chat',
    );

    _cachedUserId = result.userId;
    _didServeCachedThreads = false;
    await _hydrateCache(result.userId);

    _startSyncLoop();
    unawaited(_refreshSync(fullState: false));

    return MatrixCredentials(
      userId: result.userId,
      accessToken: result.accessToken,
      deviceId: result.deviceId,
    );
  }

  Future<void> logout() async {
    if (!_initialized) return;
    _stopSyncLoop();
    await _endCallSession(clearSnapshot: true);
    await _core.logout();
    _cachedThreads = const <ChatThread>[];
    _syncedUnreadByRoom.clear();
    _cachedMessagesByRoom.clear();
    _typingUsersByRoom.clear();
    _readReceiptsByRoomEvent.clear();
    _participantsCache.clear();
    _participantsCacheAt.clear();
    _userSearchCache.clear();
    _cachedUserId = null;
    _didServeCachedThreads = false;
  }

  Future<List<ChatThread>> getJoinedThreads({
    void Function(double progress, String status)? onProgress,
  }) async {
    if (_cachedThreads.isNotEmpty && !_didServeCachedThreads) {
      _didServeCachedThreads = true;
      unawaited(_refreshSync(fullState: false));
      // Only repair threads that are actually missing data (title/last-message).
      // forceAll was causing /state + /messages fetches for every room on
      // every app start, hammering the server.
      _scheduleThreadIntegrityRepair(_cachedThreads, forceAll: false);
      onProgress?.call(0.98, 'Loading conversations...');
      _perfLog(
        'getJoinedThreads.cacheHit',
        Stopwatch()..start(),
        <String, Object?>{'rooms': _cachedThreads.length},
        true,
      );
      return List<ChatThread>.from(_cachedThreads);
    }

    final totalStopwatch = Stopwatch()..start();
    await initialize();
    final incrementalSyncStopwatch = Stopwatch()..start();
    var sync = await _core.sync(timeoutMs: 0, fullState: false);
    _perfLog('getJoinedThreads.sync.incremental', incrementalSyncStopwatch);
    _captureTyping(sync);

    final rooms = <ChatThread>[];
    var roomsData = (sync['rooms'] as Map?) ?? const <String, dynamic>{};
    var joined = (roomsData['join'] as Map?) ?? const <String, dynamic>{};
    var invited = (roomsData['invite'] as Map?) ?? const <String, dynamic>{};
    var usedFullStateFallback = false;
    var fallbackStateLoads = 0;
    var fallbackLatestMessageLoads = 0;

    // Incremental sync may legitimately return no changed room sections.
    // If we already have cached threads, reuse them and avoid expensive
    // full-state round-trips on every thread refresh.
    if (joined.isEmpty && invited.isEmpty) {
      if (_cachedThreads.isNotEmpty) {
        _scheduleThreadIntegrityRepair(_cachedThreads, forceAll: false);
        onProgress?.call(0.98, 'Loading conversations...');
        _perfLog(
          'getJoinedThreads.reuseCachedNoDelta',
          Stopwatch()..start(),
          <String, Object?>{'rooms': _cachedThreads.length},
          true,
        );
        return List<ChatThread>.from(_cachedThreads);
      } else {
        final fullStateSyncStopwatch = Stopwatch()..start();
        sync = await _core.sync(timeoutMs: 0, fullState: true);
        _perfLog('getJoinedThreads.sync.fullState', fullStateSyncStopwatch);
        _captureTyping(sync);
        roomsData = (sync['rooms'] as Map?) ?? const <String, dynamic>{};
        joined = (roomsData['join'] as Map?) ?? const <String, dynamic>{};
        invited = (roomsData['invite'] as Map?) ?? const <String, dynamic>{};
        usedFullStateFallback = true;
      }
    }

    final totalRooms = joined.length + invited.length;
    var processedRooms = 0;
    if (totalRooms > 0) {
      onProgress?.call(0.72, 'Loading conversations... 0/$totalRooms');
    }

    for (final entry in joined.entries) {
      final roomId = entry.key.toString();
      final roomData = _asMap(entry.value);
      var stateEvents = _asList(roomData['state']);
      final timelineEvents = _asList(roomData['timeline']);
      var title = _roomTitle(roomId, stateEvents);
      var avatarUrl = _roomAvatarUrl(stateEvents);
      if (stateEvents.isEmpty || title == roomId || avatarUrl == null) {
        final fallbackStateEvents = await _loadRoomStateEvents(roomId);
        if (fallbackStateEvents.isNotEmpty) {
          fallbackStateLoads++;
          stateEvents = fallbackStateEvents;
          title = _roomTitle(roomId, stateEvents);
          avatarUrl = _roomAvatarUrl(stateEvents);
        }
      }
      _cacheParticipantsFromStateEvents(roomId, stateEvents);
      final isDm = _isLikelyDm(stateEvents);
      if (isDm) {
        final counterpart = _directMessageCounterpartForRoom(
          roomId,
          stateEvents,
        );
        if (counterpart != null) {
          title = counterpart.displayName;
          avatarUrl = counterpart.avatarUrl ?? avatarUrl;
        }
      }
      final cachedPreview = (_lastMessagePreviewByRoom[roomId] ?? '').trim();
      var lastEvent = _latestMessageEvent(timelineEvents);
      if (lastEvent == null && cachedPreview.isEmpty) {
        fallbackLatestMessageLoads++;
        lastEvent = await _loadLatestMessageEvent(roomId);
      }
      final updatedAt = lastEvent != null
          ? _roomEventDate(lastEvent, stateEvents)
          : (_lastMessageTimeByRoom[roomId] ??
                _getRoomCreationDate(stateEvents) ??
                DateTime.now());
      final cachedSenderEntry = _lastMessageSenderByRoom[roomId] ?? '';
      final cachedIsMe = cachedSenderEntry == 'me';
      final resolvedSenderName = lastEvent != null
          ? _eventSenderLabel(lastEvent, stateEvents)
          : (cachedIsMe ? '' : cachedSenderEntry);
      final senderName = resolvedSenderName;
      final previewBody = lastEvent != null
          ? _displayBodyFromEvent(lastEvent)
          : cachedPreview;
      final lastEventSenderId = lastEvent != null
          ? (lastEvent['sender'] ?? '').toString()
          : '';
      final isMe = lastEvent != null
          ? (lastEventSenderId.isNotEmpty &&
                lastEventSenderId == (currentUserId ?? ''))
          : cachedIsMe;
      final body = _formatThreadPreview(
        senderName: senderName,
        body: previewBody,
        isMe: isMe,
      );
      final existingThread = _cachedThreadById(roomId);
      if (lastEvent != null) {
        _lastMessageTimeByRoom[roomId] = updatedAt;
        _lastMessagePreviewByRoom[roomId] = previewBody;
        _lastMessageSenderByRoom[roomId] = isMe ? 'me' : senderName;
        _lastMessageSenderIdByRoom[roomId] = lastEventSenderId;
      }
      // Use _notificationCountOrNull so that if Synapse omits
      // unread_notifications (e.g. the count didn't change in this sync
      // cycle — common when the room appears only due to a typing event),
      // the existing cached count is preserved instead of being reset to 0.
      final unread =
          _notificationCountOrNull(roomData) ??
          existingThread?.unreadCount ??
          0;

      final thread = _mergeThreadDisplayFallbacks(
        ChatThread(
          id: roomId,
          title: title,
          updatedAt: updatedAt,
          lastMessage: body,
          unreadCount: unread,
          avatarUrl: avatarUrl,
          type: isDm ? ChatType.dm : ChatType.group,
          isInvited: false,
        ),
        existing: existingThread,
      );
      if (!_shouldHideIncompleteThread(thread, existing: existingThread)) {
        rooms.add(thread);
      }
      processedRooms++;
      await _reportThreadBuildProgress(
        processedRooms: processedRooms,
        totalRooms: totalRooms,
        onProgress: onProgress,
      );
    }

    for (final entry in invited.entries) {
      final roomId = entry.key.toString();
      final roomData = _asMap(entry.value);
      final inviteState = _asList(roomData['invite_state']);
      final stateEvents = _eventsFromEnvelope(inviteState);
      var title = _roomTitle(roomId, stateEvents);
      var avatarUrl = _roomAvatarUrl(stateEvents);
      _cacheParticipantsFromStateEvents(roomId, stateEvents);
      final isDm = _isLikelyDm(stateEvents);
      if (isDm) {
        final counterpart = _directMessageCounterpartForRoom(
          roomId,
          stateEvents,
        );
        if (counterpart != null) {
          title = counterpart.displayName;
          avatarUrl = counterpart.avatarUrl ?? avatarUrl;
        }
      }

      // For invitations, use room creation time or current time
      final inviteUpdatedAt =
          _getRoomCreationDate(stateEvents) ?? DateTime.now();
      final existingThread = _cachedThreadById(roomId);
      rooms.add(
        _mergeThreadDisplayFallbacks(
          ChatThread(
            id: roomId,
            title: title,
            updatedAt: inviteUpdatedAt,
            lastMessage: 'Invitation pending',
            unreadCount: 0,
            avatarUrl: avatarUrl,
            type: isDm ? ChatType.dm : ChatType.group,
            isInvited: true,
          ),
          existing: existingThread,
        ),
      );
      processedRooms++;
      await _reportThreadBuildProgress(
        processedRooms: processedRooms,
        totalRooms: totalRooms,
        onProgress: onProgress,
      );
    }

    rooms.sort((a, b) {
      if (a.isInvited != b.isInvited) {
        return a.isInvited ? -1 : 1;
      }
      // Sort by most recent message timestamp (stable creation order)
      // This preserves user intuition: chats don't shuffle on sync
      return b.updatedAt.compareTo(a.updatedAt);
    });
    final shouldReplaceAll = usedFullStateFallback || _cachedThreads.isEmpty;
    final mergedRooms = _mergeThreadDelta(
      existing: _cachedThreads,
      delta: rooms,
      replaceAll: shouldReplaceAll,
    );
    _perfLog('getJoinedThreads.total', totalStopwatch, <String, Object?>{
      'rooms': mergedRooms.length,
      'deltaRooms': rooms.length,
      'joined': joined.length,
      'invited': invited.length,
      'usedFullStateFallback': usedFullStateFallback,
      'fallbackStateLoads': fallbackStateLoads,
      'fallbackLatestMessageLoads': fallbackLatestMessageLoads,
    });
    _userSearchCache.clear();
    _cachedThreads = List<ChatThread>.from(mergedRooms);
    unawaited(_persistCache());
    return mergedRooms;
  }

  Future<bool> joinRoomIfInvited(String roomId) async {
    await initialize();
    Object? joinError;
    StackTrace? joinErrorTrace;
    try {
      await _core.joinRoom(roomId);
    } catch (e, s) {
      joinError = e;
      joinErrorTrace = s;
      debugPrint(
        '[MatrixRestService] joinRoomIfInvited failed for $roomId: $e',
      );
    }

    // Poll sync until the room appears as `joined` (not `invited`) in the
    // homeserver's sync response. The join POST returns 200 before the
    // membership event is propagated, so immediately fetching messages would
    // get M_FORBIDDEN. Retry up to ~5 seconds.
    const maxAttempts = 5;
    const retryDelay = Duration(milliseconds: 1000);
    bool confirmedJoined = false;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final sync = await _core.sync(timeoutMs: 0, fullState: true);
        final rooms = _asMap(sync['rooms']);
        final joined = _asMap(rooms['join']);
        final invited = _asMap(rooms['invite']);
        _applyThreadSyncDelta(joined: joined, invited: invited);
        await _persistCache();
        if (joined.containsKey(roomId)) {
          confirmedJoined = true;
          break;
        }
      } catch (e) {
        debugPrint(
          '[MatrixRestService] post-join sync attempt $attempt failed: $e',
        );
      }
      await Future<void>.delayed(retryDelay);
    }

    if (joinError != null) {
      // If the join call threw but the room is now confirmed joined
      // (e.g. already accepted on another device), treat as success.
      if (confirmedJoined) {
        _emitSyncUpdate();
        return true;
      }
      // Propagate the real Matrix error so the UI can surface the reason.
      Error.throwWithStackTrace(
        joinError,
        joinErrorTrace ?? StackTrace.current,
      );
    }

    _emitSyncUpdate();
    return confirmedJoined;
  }

  Future<String> resolveRoomId(String roomIdOrAlias) async {
    await initialize();
    final normalized = roomIdOrAlias.trim();
    if (normalized.isEmpty || normalized.startsWith('!')) {
      return normalized;
    }
    if (!normalized.startsWith('#')) {
      return normalized;
    }

    final resolved = await _core.resolveRoomAlias(normalized);
    return resolved.trim().isEmpty ? normalized : resolved.trim();
  }

  Future<void> leaveRoom(String roomId) async {
    await initialize();
    await _core.leaveRoom(roomId);

    _cachedThreads = _cachedThreads
        .where((thread) => thread.id != roomId)
        .toList(growable: false);
    _cachedMessagesByRoom.remove(roomId);
    _roomMessageRefreshInFlight.remove(roomId);
    _roomMessageRefreshAt.remove(roomId);
    _typingUsersByRoom.remove(roomId);
    _participantsCache.remove(roomId);
    _participantsCacheAt.remove(roomId);
    _lastMessagePreviewByRoom.remove(roomId);
    _lastMessageSenderByRoom.remove(roomId);
    _lastMessageSenderIdByRoom.remove(roomId);
    _lastMessageTimeByRoom.remove(roomId);
    _threadIntegrityRepairInFlight.remove(roomId);
    _userSearchCache.clear();

    await _persistCache();
    await _refreshSync(fullState: false);
    _emitSyncUpdate();
  }

  Future<List<ChatMessage>> getRoomMessages(
    String roomId, {
    int limit = 60,
    bool allowCache = true,
  }) async {
    final cachedMessages =
        _cachedMessagesByRoom[roomId] ?? const <ChatMessage>[];
    if (allowCache && cachedMessages.isNotEmpty) {
      _scheduleRoomMessagesRefresh(roomId: roomId, limit: limit);
      _perfLog(
        'getRoomMessages.cacheHit',
        Stopwatch()..start(),
        <String, Object?>{
          'roomId': roomId,
          'messageCount': cachedMessages.length,
        },
        true,
      );
      return List<ChatMessage>.from(cachedMessages);
    }

    final totalStopwatch = Stopwatch()..start();
    await initialize();

    final fetchStopwatch = Stopwatch()..start();
    final raw = await _core.getRoomMessagesRaw(roomId, limit: limit);
    _perfLog('getRoomMessages.fetchRaw', fetchStopwatch, <String, Object?>{
      'roomId': roomId,
      'limit': limit,
    });
    final chunk = _asList(raw['chunk']);
    final participantsStopwatch = Stopwatch()..start();
    final participants = await getRoomParticipants(roomId);
    _perfLog(
      'getRoomMessages.participants',
      participantsStopwatch,
      <String, Object?>{'roomId': roomId, 'participants': participants.length},
    );
    final displayNamesByUserId = <String, String>{
      for (final participant in participants)
        participant.userId: participant.displayName,
    };
    final myUserId = currentUserId ?? '';
    final receiptsByEvent =
        _readReceiptsByRoomEvent[roomId] ?? const <String, Set<String>>{};

    final eventsById = <String, Map<String, dynamic>>{};
    final redactedEventIds = <String>{};
    final replacementBodyByTarget = <String, String>{};
    final reactionEventsByTarget = <String, List<Map<String, dynamic>>>{};

    for (final event in chunk) {
      final map = _asMap(event);
      final eventId = (map['event_id'] ?? '').toString();
      if (eventId.isEmpty) continue;
      eventsById[eventId] = map;

      final eventType = (map['type'] ?? '').toString();
      if (eventType == 'm.reaction') {
        final relatesTo = _asMap(_asMap(map['content'])['m.relates_to']);
        final target = (relatesTo['event_id'] ?? '').toString();
        final key = (relatesTo['key'] ?? '').toString();
        if (target.isNotEmpty && key.isNotEmpty) {
          reactionEventsByTarget
              .putIfAbsent(target, () => <Map<String, dynamic>>[])
              .add({
                'eventId': eventId,
                'senderId': (map['sender'] ?? '').toString(),
                'key': key,
              });
        }
      }

      if (eventType == 'm.room.redaction') {
        final target = (map['redacts'] ?? '').toString();
        if (target.isNotEmpty) {
          redactedEventIds.add(target);
        }
      }

      if (eventType == 'm.room.message') {
        final content = _asMap(map['content']);
        final relatesTo = _asMap(content['m.relates_to']);
        if ((relatesTo['rel_type'] ?? '').toString() == 'm.replace') {
          final target = (relatesTo['event_id'] ?? '').toString();
          final newContent = _asMap(content['m.new_content']);
          final newBody = (newContent['body'] ?? '').toString();
          if (target.isNotEmpty && newBody.trim().isNotEmpty) {
            replacementBodyByTarget[target] = newBody;
          }
        }
      }
    }

    var droppedRedactedLikeEvents = 0;
    final messageEvents =
        chunk
            .map(_asMap)
            .where((event) {
              final eventType = (event['type'] ?? '').toString();
              if (eventType == 'm.call.invite') {
                return true;
              }
              if (_isJoinMembershipEvent(event)) {
                return true;
              }
              if (_isProfileDisplayNameChangeEvent(event)) {
                return true;
              }
              if (_isProfileAvatarChangeEvent(event)) {
                return true;
              }
              final eventId = (event['event_id'] ?? '').toString();
              if (redactedEventIds.contains(eventId)) {
                droppedRedactedLikeEvents++;
                return false;
              }
              final unsigned = _asMap(event['unsigned']);
              if (unsigned.containsKey('redacted_because') ||
                  unsigned.containsKey('redacted_by')) {
                droppedRedactedLikeEvents++;
                return false;
              }
              final content = _asMap(event['content']);
              final msgType = (content['msgtype'] ?? '').toString().trim();
              final body = (content['body'] ?? '').toString().trim();
              final formattedBody = (content['formatted_body'] ?? '')
                  .toString()
                  .trim();
              final relatesTo = _asMap(content['m.relates_to']);
              final mediaUrl = _mediaUrl(content);
              final filename = (content['filename'] ?? content['body'] ?? '')
                  .toString()
                  .trim();
              final caption = (content['org.cluborbit.caption'] ?? '')
                  .toString()
                  .trim();
              final newContent = _asMap(content['m.new_content']);
              final strippedRedactionPayload =
                  eventType == 'm.room.message' &&
                  msgType.isEmpty &&
                  body.isEmpty &&
                  formattedBody.isEmpty &&
                  relatesTo.isEmpty &&
                  (mediaUrl == null || mediaUrl.trim().isEmpty) &&
                  filename.isEmpty &&
                  caption.isEmpty &&
                  newContent.isEmpty;
              final strippedMediaPayload =
                  eventType == 'm.room.message' &&
                  (msgType == 'm.image' ||
                      msgType == 'm.video' ||
                      msgType == 'm.file') &&
                  body.isEmpty &&
                  (mediaUrl == null || mediaUrl.trim().isEmpty) &&
                  filename.isEmpty &&
                  caption.isEmpty;
              if (strippedRedactionPayload) {
                droppedRedactedLikeEvents++;
                return false;
              }
              if (strippedMediaPayload) {
                droppedRedactedLikeEvents++;
                return false;
              }
              return eventType == 'm.room.message' &&
                  (_asMap(event['content'])['m.relates_to']
                          as Map?)?['rel_type'] !=
                      'm.replace';
            })
            .toList(growable: false)
          ..sort((a, b) {
            final aTs = _eventTimestamp(a);
            final bTs = _eventTimestamp(b);
            final byTs = aTs.compareTo(bTs);
            if (byTs != 0) {
              return byTs;
            }
            final aId = (a['event_id'] ?? '').toString();
            final bId = (b['event_id'] ?? '').toString();
            return aId.compareTo(bId);
          });

    final latestReadIndexByUserId = <String, int>{};
    for (var index = 0; index < messageEvents.length; index++) {
      final eventId = (messageEvents[index]['event_id'] ?? '').toString();
      if (eventId.isEmpty) {
        continue;
      }
      final readers = receiptsByEvent[eventId] ?? const <String>{};
      for (final userId in readers) {
        if (userId.isEmpty) {
          continue;
        }
        final previous = latestReadIndexByUserId[userId];
        if (previous == null || index > previous) {
          latestReadIndexByUserId[userId] = index;
        }
      }
    }

    var droppedEmptyMessagePayloads = 0;
    final messages = <ChatMessage>[];
    for (
      var messageIndex = 0;
      messageIndex < messageEvents.length;
      messageIndex++
    ) {
      final event = messageEvents[messageIndex];
      final eventId = (event['event_id'] ?? '').toString();
      if (eventId.isEmpty) continue;

      final eventType = (event['type'] ?? '').toString();
      final content = _asMap(event['content']);
      final senderId = (event['sender'] ?? '').toString();
      final senderName = _resolveSenderName(senderId, displayNamesByUserId);

      final isCallInvite = eventType == 'm.call.invite';
      final isJoinEvent = _isJoinMembershipEvent(event);
      final isDisplayNameChangeEvent = _isProfileDisplayNameChangeEvent(event);
      final isAvatarChangeEvent = _isProfileAvatarChangeEvent(event);
      final isTimelineOnlyStateEvent =
          isCallInvite ||
          isJoinEvent ||
          isDisplayNameChangeEvent ||
          isAvatarChangeEvent;
      final kind = isTimelineOnlyStateEvent
          ? MessageKind.text
          : _mapMessageKind(content);
      final replyToEventId = isTimelineOnlyStateEvent
          ? null
          : _extractReplyEventId(content);

      String? replyToBody;
      String? replyToSenderName;
      String? replyToKind;
      String? replyToMediaUrl;
      String? replyToThumbnailUrl;
      bool replyToIsForwarded = false;

      if (replyToEventId != null && replyToEventId.isNotEmpty) {
        final related =
            eventsById[replyToEventId] ??
            await _safeGetEvent(roomId: roomId, eventId: replyToEventId);
        if (related != null) {
          final relatedContent = _asMap(related['content']);
          final relatedKind = _mapMessageKind(relatedContent);
          final relatedBody = _replyPreviewBodyFromContent(relatedContent);
          final relatedSenderId = (related['sender'] ?? '').toString();
          final relatedMediaUrl = _mediaUrl(relatedContent);
          final relatedThumb = _thumbnailUrl(relatedContent);
          final relatedForwarded = _hasForwardPrefix(relatedBody);

          replyToBody = _stripForwardPrefix(relatedBody);
          replyToSenderName = _resolveSenderName(
            relatedSenderId,
            displayNamesByUserId,
          );
          replyToKind = relatedKind.name;
          replyToMediaUrl = relatedMediaUrl;
          replyToThumbnailUrl = relatedThumb;
          replyToIsForwarded = relatedForwarded;
        }
      }

      final originalBody = isCallInvite
          ? _callInviteTimelineBody(senderName: senderName, content: content)
          : isJoinEvent
          ? _joinTimelineBody(
              event: event,
              senderName: senderName,
              displayNamesByUserId: displayNamesByUserId,
            )
          : isDisplayNameChangeEvent && isAvatarChangeEvent
          ? _profileUpdateTimelineBody(
              event: event,
              senderName: senderName,
              displayNamesByUserId: displayNamesByUserId,
              changedAvatar: true,
              changedDisplayName: true,
            )
          : isDisplayNameChangeEvent
          ? _profileUpdateTimelineBody(
              event: event,
              senderName: senderName,
              displayNamesByUserId: displayNamesByUserId,
              changedAvatar: false,
              changedDisplayName: true,
            )
          : isAvatarChangeEvent
          ? _profileUpdateTimelineBody(
              event: event,
              senderName: senderName,
              displayNamesByUserId: displayNamesByUserId,
              changedAvatar: true,
              changedDisplayName: false,
            )
          : _bodyFromContent(content);
      final replacedBody = isTimelineOnlyStateEvent
          ? null
          : replacementBodyByTarget[eventId];
      final effectiveBody = replacedBody ?? originalBody;
      final forwarded =
          (!isTimelineOnlyStateEvent && _hasForwardPrefix(effectiveBody)) ||
          content['org.cluborbit.forwarded'] == true;

      final mediaUrl = _mediaUrl(content);
      final thumbnailUrl = _thumbnailUrl(content);
      final filename = (content['body'] ?? '').toString();
      final captionRaw = content['org.cluborbit.caption'];
      final caption = captionRaw is String ? captionRaw.trim() : '';
      final reactionEvents =
          reactionEventsByTarget[eventId] ?? const <Map<String, dynamic>>[];
      final readCount = latestReadIndexByUserId.entries
          .where(
            (entry) =>
                entry.key != myUserId &&
                entry.key != senderId &&
                entry.value >= messageIndex,
          )
          .length;
      final pollVotes = reactionEvents
          .where((entry) => (entry['key'] ?? '').toString().startsWith('poll:'))
          .map((entry) {
            final key = (entry['key'] ?? '').toString();
            final optionIndex = int.tryParse(key.substring('poll:'.length));
            return <String, dynamic>{
              'eventId': entry['eventId'],
              'senderId': entry['senderId'],
              'optionIndex': optionIndex,
            };
          })
          .where((entry) => entry['optionIndex'] is int)
          .toList(growable: false);

      final metadata = <String, dynamic>{
        'timelineOnly': isTimelineOnlyStateEvent,
        'timelineEventType': isCallInvite
            ? 'call_started'
            : isJoinEvent
            ? 'member_joined'
            : isDisplayNameChangeEvent && isAvatarChangeEvent
            ? 'member_profile_updated'
            : isDisplayNameChangeEvent
            ? 'member_display_name_changed'
            : isAvatarChangeEvent
            ? 'member_avatar_changed'
            : null,
        'isVideoCall': isCallInvite ? _isVideoCallContent(content) : null,
        'isForwarded': forwarded,
        'mediaUrl': mediaUrl,
        'thumbnailUrl': thumbnailUrl,
        'mimeType': _asMap(content['info'])['mimetype'],
        'filename': filename,
        'caption': caption,
        'reactions': reactionEvents
            .map((entry) => (entry['key'] ?? '').toString())
            .toList(growable: false),
        'reactionEvents': reactionEvents,
        'pollVotes': pollVotes,
        'replyToKind': replyToKind,
        'replyToMediaUrl': replyToMediaUrl,
        'replyToThumbnailUrl': replyToThumbnailUrl,
        'replyToIsForwarded': replyToIsForwarded,
        'sendStage': senderId == myUserId
            ? (readCount > 0 ? 'read' : 'delivered')
            : null,
      };

      if (!isTimelineOnlyStateEvent) {
        final hasRenderableText = _stripForwardPrefix(
          effectiveBody,
        ).trim().isNotEmpty;
        final hasRenderableMedia =
            (mediaUrl ?? '').trim().isNotEmpty ||
            (thumbnailUrl ?? '').trim().isNotEmpty ||
            filename.trim().isNotEmpty ||
            caption.isNotEmpty;
        if (!hasRenderableText && !hasRenderableMedia) {
          droppedEmptyMessagePayloads++;
          continue;
        }
      }

      messages.add(
        ChatMessage(
          id: eventId,
          roomId: roomId,
          senderId: senderId,
          senderName: senderName,
          body: _stripForwardPrefix(effectiveBody),
          kind: kind,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            _eventTimestamp(event),
            isUtc: true,
          ),
          replyToEventId: replyToEventId,
          replyToSenderName: replyToSenderName,
          replyToBody: replyToBody,
          isEdited: replacedBody != null,
          readCount: readCount,
          metadata: metadata,
        ),
      );
    }

    if (messages.isNotEmpty) {
      final latest = messages.last;
      final mimeRaw = latest.metadata['mimeType'];
      final mime = mimeRaw is String ? mimeRaw.trim().toLowerCase() : '';
      final filenameRaw = latest.metadata['filename'];
      final filename = filenameRaw is String ? filenameRaw.trim() : '';
      if (_isAudioFile(mimeType: mime, filename: filename)) {
        _lastMessagePreviewByRoom[roomId] = '🎤 Voice message';
      } else if ((latest.metadata['mediaUrl'] ?? '').toString().isNotEmpty) {
        _lastMessagePreviewByRoom[roomId] = '📎 [File]';
      } else {
        _lastMessagePreviewByRoom[roomId] = latest.body;
      }
      final senderLabel = _sanitizeSenderLabel(latest.senderName);
      final latestIsMe =
          (currentUserId ?? '').isNotEmpty &&
          latest.senderId.trim() == (currentUserId ?? '').trim();
      if (latestIsMe) {
        _lastMessageSenderByRoom[roomId] = 'me';
      } else if (senderLabel.isNotEmpty) {
        _lastMessageSenderByRoom[roomId] = senderLabel;
      }
      _lastMessageSenderIdByRoom[roomId] = latest.senderId.trim();
      _lastMessageTimeByRoom[roomId] = latest.createdAt;
    }

    _perfLog('getRoomMessages.total', totalStopwatch, <String, Object?>{
      'roomId': roomId,
      'limit': limit,
      'chunkEvents': chunk.length,
      'messageCount': messages.length,
      'droppedRedactedLikeEvents': droppedRedactedLikeEvents,
      'droppedEmptyMessagePayloads': droppedEmptyMessagePayloads,
    });

    final existingCached =
        _cachedMessagesByRoom[roomId] ?? const <ChatMessage>[];
    final mergedMessages = allowCache
        ? _mergeCachedRoomMessages(existing: existingCached, incoming: messages)
        : _mergeFreshRoomMessages(existing: existingCached, incoming: messages);
    _cachedMessagesByRoom[roomId] = mergedMessages;
    await _persistCache();

    return mergedMessages;
  }

  Future<void> setReadMarker(String roomId) async {
    await initialize();
    final raw = await _core.getRoomMessagesRaw(roomId, limit: 1);
    final chunk = _asList(raw['chunk']);
    if (chunk.isEmpty) return;
    final latest = _asMap(chunk.first);
    final eventId = (latest['event_id'] ?? '').toString();
    if (eventId.isEmpty) return;
    await _core.setReadMarker(roomId: roomId, eventId: eventId);
    // Room is now read — clear the synced unread override so cachedThreads
    // reflects 0 immediately rather than waiting for the next sync cycle.
    _syncedUnreadByRoom.remove(roomId);
  }

  Future<String> sendTextMessage({
    required String roomId,
    required String text,
    String? replyToEventId,
    bool isForwarded = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    await initialize();
    final payload = isForwarded ? '$_forwardedPrefix$text' : text;
    final eventId = await _core.sendText(
      roomId,
      payload,
      replyToEventId: replyToEventId,
    );
    final now = DateTime.now();
    final previewBody = _stripForwardPrefix(payload).trim();
    _updateLocalThreadPreviewAfterSend(
      roomId: roomId,
      previewBody: previewBody.isEmpty ? 'Message' : previewBody,
      createdAt: now,
    );
    _appendOptimisticCachedMessage(
      roomId: roomId,
      message: ChatMessage(
        id: eventId,
        roomId: roomId,
        senderId: (currentUserId ?? '').trim(),
        senderName: 'You',
        body: previewBody.isEmpty ? 'Message' : previewBody,
        kind: MessageKind.text,
        createdAt: now,
        metadata: const <String, dynamic>{'sendStage': 'sent'},
      ),
    );
    await _persistCache();
    _perfLog('sendTextMessage', stopwatch, <String, Object?>{
      'roomId': roomId,
      'payloadChars': payload.length,
      'reply': replyToEventId != null,
    });
    return eventId;
  }

  Future<String> sendEmojiMessage({
    required String roomId,
    required String emoji,
    String? replyToEventId,
  }) {
    return sendTextMessage(
      roomId: roomId,
      text: emoji,
      replyToEventId: replyToEventId,
    );
  }

  ChatMessage createOptimisticTextMessage({
    required String roomId,
    required String body,
    required MessageKind kind,
    String? replyToEventId,
    String? replyToSenderName,
    String? replyToBody,
    bool isForwarded = false,
  }) {
    final createdAt = DateTime.now();
    final optimistic = ChatMessage(
      id: '$_localMessagePrefix${createdAt.microsecondsSinceEpoch}',
      roomId: roomId,
      senderId: (currentUserId ?? '').trim(),
      senderName: 'You',
      body: body,
      kind: kind,
      createdAt: createdAt,
      replyToEventId: replyToEventId,
      replyToSenderName: replyToSenderName,
      replyToBody: replyToBody,
      metadata: <String, dynamic>{
        'sendStage': 'local',
        'isForwarded': isForwarded,
      },
    );

    _updateLocalThreadPreviewAfterSend(
      roomId: roomId,
      previewBody: body.isEmpty ? 'Message' : body,
      createdAt: createdAt,
    );
    _appendOptimisticCachedMessage(roomId: roomId, message: optimistic);
    unawaited(_persistCache());
    return optimistic;
  }

  Future<ChatMessage> sendStagedTextMessage({
    required ChatMessage optimisticMessage,
    required String text,
    String? replyToEventId,
    bool isForwarded = false,
  }) async {
    await initialize();
    final payload = isForwarded ? '$_forwardedPrefix$text' : text;
    final eventId = await _core.sendText(
      optimisticMessage.roomId,
      payload,
      replyToEventId: replyToEventId,
    );

    final sentMessage = optimisticMessage.copyWith(
      id: eventId,
      metadata: <String, dynamic>{
        ...optimisticMessage.metadata,
        'sendStage': 'sent',
      },
    );
    _replaceCachedMessage(
      roomId: optimisticMessage.roomId,
      previousId: optimisticMessage.id,
      replacement: sentMessage,
    );
    await _persistCache();
    return sentMessage;
  }

  void markStagedMessageFailed(ChatMessage message) {
    final failed = message.copyWith(
      metadata: <String, dynamic>{...message.metadata, 'sendStage': 'failed'},
    );
    _replaceCachedMessage(
      roomId: failed.roomId,
      previousId: message.id,
      replacement: failed,
    );
    unawaited(_persistCache());
  }

  Future<void> setTyping({
    required String roomId,
    required bool isTyping,
  }) async {
    await initialize();
    try {
      await _core.setTyping(roomId: roomId, isTyping: isTyping);
    } catch (_) {
      // Typing notifications are best-effort; ignore transient/disposed errors.
    }
  }

  Future<List<ChatParticipant>> getTypingUsers(String roomId) async {
    await initialize();
    final myUserId = currentUserId;
    final ids = (_typingUsersByRoom[roomId] ?? const <String>{})
        .where((id) => id != myUserId)
        .toList(growable: false);
    final cachedParticipants =
        _participantsCache[roomId] ?? const <ChatParticipant>[];
    final displayById = <String, String>{
      for (final participant in cachedParticipants)
        participant.userId: participant.displayName,
    };

    return ids
        .map(
          (id) => ChatParticipant(
            userId: id,
            displayName: _sanitizeSenderLabel(displayById[id] ?? '') == ''
                ? id
                : _sanitizeSenderLabel(displayById[id] ?? ''),
            level: ChatMemberLevel.member,
            membership: 'typing',
            avatarUrl: null,
          ),
        )
        .toList(growable: false);
  }

  Future<String> sendMediaMessage({
    required String roomId,
    required List<int> bytes,
    required String filename,
    required String mimeType,
    required MessageKind kind,
    String? caption,
    bool isForwarded = false,
  }) async {
    final totalStopwatch = Stopwatch()..start();
    await initialize();

    final uploadStopwatch = Stopwatch()..start();
    final mxc = await _core.uploadMedia(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
    _perfLog('sendMediaMessage.upload', uploadStopwatch, <String, Object?>{
      'roomId': roomId,
      'filename': filename,
      'bytes': bytes.length,
      'mimeType': mimeType,
    });

    final msgType = switch (kind) {
      MessageKind.image => 'm.image',
      MessageKind.video => 'm.video',
      MessageKind.emoji || MessageKind.text => 'm.file',
    };

    final eventId = await _core.sendMediaMessage(
      roomId: roomId,
      msgtype: msgType,
      body: filename,
      mxcUrl: mxc,
      mimeType: mimeType,
      caption: caption,
      isForwarded: isForwarded,
    );
    final now = DateTime.now();
    final normalizedCaption = (caption ?? '').trim();
    final previewBody = switch (kind) {
      MessageKind.image =>
        normalizedCaption.isNotEmpty ? '🖼 $normalizedCaption' : '[Image]',
      MessageKind.video =>
        normalizedCaption.isNotEmpty ? '🎬 $normalizedCaption' : '[Video]',
      MessageKind.emoji || MessageKind.text =>
        _isAudioFile(mimeType: mimeType, filename: filename)
            ? '🎤 Voice message'
            : '📎 [File]',
    };
    _updateLocalThreadPreviewAfterSend(
      roomId: roomId,
      previewBody: previewBody,
      createdAt: now,
    );
    _appendOptimisticCachedMessage(
      roomId: roomId,
      message: ChatMessage(
        id: eventId,
        roomId: roomId,
        senderId: (currentUserId ?? '').trim(),
        senderName: 'You',
        body: filename,
        kind: kind,
        createdAt: now,
        metadata: <String, dynamic>{
          'sendStage': 'sent',
          'mediaUrl': _mxcToDownloadHttp(mxc) ?? mxc,
          'thumbnailUrl': _mxcToThumbnailHttp(mxc),
          'mimeType': mimeType,
          'filename': filename,
          'caption': normalizedCaption,
        },
      ),
    );
    await _persistCache();
    _perfLog('sendMediaMessage.total', totalStopwatch, <String, Object?>{
      'roomId': roomId,
      'kind': kind.name,
      'filename': filename,
    });
    return eventId;
  }

  Future<String> editMessage({
    required String roomId,
    required String originalEventId,
    required String newBody,
  }) async {
    await initialize();
    return _core.editText(roomId, originalEventId, newBody);
  }

  Future<String> forwardMessage({
    required String roomId,
    required ChatMessage source,
  }) async {
    await initialize();

    if (source.kind == MessageKind.image || source.kind == MessageKind.video) {
      final mediaUrlRaw = source.metadata['mediaUrl'];
      final mediaUrl = mediaUrlRaw is String ? mediaUrlRaw.trim() : '';
      if (mediaUrl.isNotEmpty) {
        try {
          final bytes = await _core.downloadMedia(mediaUrl);
          final nameRaw = source.metadata['filename'];
          final filename = nameRaw is String && nameRaw.trim().isNotEmpty
              ? nameRaw.trim()
              : '${source.kind.name}_${DateTime.now().millisecondsSinceEpoch}';
          final captionRaw = source.metadata['caption'];
          final caption = captionRaw is String ? captionRaw.trim() : '';

          return sendMediaMessage(
            roomId: roomId,
            bytes: bytes,
            filename: filename,
            mimeType: _mimeTypeFromFileName(filename, source.kind),
            kind: source.kind,
            caption: caption.isEmpty ? null : caption,
            isForwarded: true,
          );
        } catch (_) {
          // Fall through to text-forward fallback.
        }
      }
    }

    final text = source.body.trim();
    return sendTextMessage(
      roomId: roomId,
      text: text.isEmpty ? 'Forwarded message' : text,
      isForwarded: true,
    );
  }

  bool _hasForwardPrefix(String body) {
    return body.startsWith(_forwardedPrefix);
  }

  String _stripForwardPrefix(String body) {
    if (_hasForwardPrefix(body)) {
      return body.substring(_forwardedPrefix.length).trim();
    }
    return body;
  }

  Future<void> redactEvent({
    required String roomId,
    required String eventId,
  }) async {
    await initialize();
    if (kDebugMode) {
      debugPrint(
        '[MatrixRestService.redactEvent] roomId=$roomId eventId=$eventId start',
      );
    }
    try {
      await _core.redact(roomId: roomId, eventId: eventId);
      if (kDebugMode) {
        debugPrint(
          '[MatrixRestService.redactEvent] roomId=$roomId eventId=$eventId success',
        );
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[MatrixRestService.redactEvent] roomId=$roomId eventId=$eventId failed error=$error',
        );
        debugPrint('[MatrixRestService.redactEvent] stack=$stackTrace');
      }
      rethrow;
    }
  }

  Future<void> sendReaction({
    required String roomId,
    required String eventId,
    required String emoji,
  }) async {
    await initialize();
    await _core.sendReaction(roomId: roomId, eventId: eventId, emoji: emoji);
  }

  Future<void> sendPollVote({
    required String roomId,
    required String eventId,
    required int optionIndex,
    List<String> priorVoteEventIds = const <String>[],
    bool sendVote = true,
  }) async {
    await initialize();
    for (final priorVoteEventId in priorVoteEventIds) {
      if (priorVoteEventId.isEmpty) {
        continue;
      }
      await _core.redact(roomId: roomId, eventId: priorVoteEventId);
    }
    if (!sendVote) {
      return;
    }
    await _core.sendReaction(
      roomId: roomId,
      eventId: eventId,
      emoji: 'poll:$optionIndex',
    );
  }

  Future<void> startCall({
    required String roomId,
    required bool isVideo,
  }) async {
    await initialize();
    if (_activeCallId != null) {
      throw StateError(_collisionMessage());
    }

    final callId = _nextCallId();
    _activeCallIsIncoming = false;
    await _ensurePeerConnection(
      roomId: roomId,
      callId: callId,
      isVideo: isVideo,
    );

    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      throw StateError('Could not create peer connection.');
    }

    final offer = await peerConnection.createOffer(<String, dynamic>{
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isVideo ? 1 : 0,
    });
    await peerConnection.setLocalDescription(offer);
    await sendCallInviteSignal(
      roomId: roomId,
      callId: callId,
      offerSdp: offer.sdp ?? '',
      isVideo: isVideo,
    );
    _armOutgoingRingTimeout(callId: callId, roomId: roomId, isVideo: isVideo);

    _publishSnapshot(
      ChatCallSnapshot(
        phase: ChatCallPhase.connecting,
        isVideo: isVideo,
        isIncoming: false,
        microphoneMuted: false,
        videoMuted: false,
        speakerOn: false,
      ),
    );
  }

  Future<MatrixTurnServerInfo?> getTurnServerInfo() async {
    await initialize();
    try {
      return await _resolveTurnServerInfoOrThrow();
    } catch (_) {
      return null;
    }
  }

  Future<String> sendCallInviteSignal({
    required String roomId,
    required String callId,
    required String offerSdp,
    required bool isVideo,
    int lifetimeMs = 60000,
  }) async {
    await initialize();
    final eventId = await _core.sendCallEvent(
      roomId: roomId,
      eventType: 'm.call.invite',
      content: <String, dynamic>{
        'call_id': callId,
        'version': '1',
        'lifetime': lifetimeMs,
        'offer': <String, dynamic>{'type': 'offer', 'sdp': offerSdp},
      },
    );
    _activeCallId = callId;
    _activeCallRoomId = roomId;
    _activeCallIsVideo = isVideo;
    _activeCallIsIncoming = false;
    _publishSnapshot(
      ChatCallSnapshot(
        phase: ChatCallPhase.connecting,
        isVideo: isVideo,
        isIncoming: false,
        microphoneMuted: false,
        videoMuted: false,
        speakerOn: false,
      ),
    );
    return eventId;
  }

  Future<String> sendCallAnswerSignal({
    required String roomId,
    required String callId,
    required String answerSdp,
    required bool isVideo,
  }) async {
    await initialize();
    final eventId = await _core.sendCallEvent(
      roomId: roomId,
      eventType: 'm.call.answer',
      content: <String, dynamic>{
        'call_id': callId,
        'version': '1',
        'answer': <String, dynamic>{'type': 'answer', 'sdp': answerSdp},
      },
    );
    _activeCallId = callId;
    _activeCallRoomId = roomId;
    _activeCallIsVideo = isVideo;
    _activeCallIsIncoming = true;
    _cancelOutgoingRingTimeout();
    _armConnectingTimeout();
    _publishSnapshot(
      ChatCallSnapshot(
        phase: ChatCallPhase.connected,
        isVideo: isVideo,
        isIncoming: false,
        microphoneMuted: false,
        videoMuted: false,
        speakerOn: false,
      ),
    );
    return eventId;
  }

  Future<String> sendCallCandidatesSignal({
    required String roomId,
    required String callId,
    required List<Map<String, dynamic>> candidates,
  }) async {
    await initialize();
    return _core.sendCallEvent(
      roomId: roomId,
      eventType: 'm.call.candidates',
      content: <String, dynamic>{
        'call_id': callId,
        'version': '1',
        'candidates': candidates,
      },
    );
  }

  Future<String> sendCallHangupSignal({
    required String roomId,
    required String callId,
    String reason = 'user_hangup',
  }) async {
    await initialize();
    final eventId = await _core.sendCallEvent(
      roomId: roomId,
      eventType: 'm.call.hangup',
      content: <String, dynamic>{
        'call_id': callId,
        'version': '1',
        'reason': reason,
      },
    );
    return eventId;
  }

  Future<String> sendCallRejectSignal({
    required String roomId,
    required String callId,
    String reason = 'user_reject',
  }) async {
    await initialize();
    return _core.sendCallEvent(
      roomId: roomId,
      eventType: 'm.call.reject',
      content: <String, dynamic>{
        'call_id': callId,
        'version': '1',
        'reason': reason,
      },
    );
  }

  Future<void> answerActiveCall() async {
    await initialize();
    final callId = _incomingCallId;
    final roomId = _incomingCallRoomId;
    final offerSdp = _incomingOfferSdp;
    if (callId == null || roomId == null || offerSdp == null) {
      throw StateError('No incoming call to answer.');
    }

    await _ensurePeerConnection(
      roomId: roomId,
      callId: callId,
      isVideo: _activeCallIsVideo,
    );
    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      throw StateError('Could not create peer connection.');
    }

    await peerConnection.setRemoteDescription(
      RTCSessionDescription(offerSdp, 'offer'),
    );
    await _drainPendingRemoteCandidates();

    final answer = await peerConnection.createAnswer(<String, dynamic>{
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': _activeCallIsVideo ? 1 : 0,
    });
    await peerConnection.setLocalDescription(answer);
    await sendCallAnswerSignal(
      roomId: roomId,
      callId: callId,
      answerSdp: answer.sdp ?? '',
      isVideo: _activeCallIsVideo,
    );
    _cancelIncomingRingTimeout();
    _armConnectingTimeout();

    _incomingCallId = null;
    _incomingCallRoomId = null;
    _incomingOfferSdp = null;
    _publishSnapshot(
      ChatCallSnapshot(
        phase: ChatCallPhase.connected,
        isVideo: _activeCallIsVideo,
        isIncoming: false,
        microphoneMuted: _callSnapshot.microphoneMuted,
        videoMuted: _callSnapshot.videoMuted,
        speakerOn: _callSnapshot.speakerOn,
        remoteUserId: _incomingCallerUserId,
        remoteDisplayName: _incomingCallerDisplayName,
      ),
    );
  }

  Future<void> rejectActiveCall() async {
    await initialize();
    final callId = _incomingCallId;
    final roomId = _incomingCallRoomId;
    if (callId == null || roomId == null) {
      return;
    }
    await sendCallRejectSignal(roomId: roomId, callId: callId);
    await _endCallSession(
      clearSnapshot: false,
      promoteQueuedIncoming: true,
      snapshot: ChatCallSnapshot(
        phase: ChatCallPhase.ended,
        isVideo: _activeCallIsVideo,
        isIncoming: false,
        microphoneMuted: false,
        videoMuted: false,
        speakerOn: false,
        remoteUserId: _incomingCallerUserId,
        remoteDisplayName: _incomingCallerDisplayName,
      ),
    );
  }

  Future<void> hangupActiveCall() async {
    await initialize();
    final callId = _activeCallId;
    final roomId = _activeCallRoomId;
    if (callId != null && roomId != null) {
      await sendCallHangupSignal(roomId: roomId, callId: callId);
    }
    await _endCallSession(
      clearSnapshot: false,
      promoteQueuedIncoming: true,
      snapshot: ChatCallSnapshot(
        phase: ChatCallPhase.ended,
        isVideo: _activeCallIsVideo,
        isIncoming: false,
        microphoneMuted: false,
        videoMuted: false,
        speakerOn: false,
      ),
    );
  }

  Future<void> setMicrophoneMuted(bool muted) async {
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !muted;
      }
    }
    _publishSnapshot(
      ChatCallSnapshot(
        phase: _callSnapshot.phase,
        isVideo: _callSnapshot.isVideo,
        isIncoming: _callSnapshot.isIncoming,
        microphoneMuted: muted,
        videoMuted: _callSnapshot.videoMuted,
        speakerOn: _callSnapshot.speakerOn,
        remoteUserId: _callSnapshot.remoteUserId,
        remoteDisplayName: _callSnapshot.remoteDisplayName,
        remoteAvatarUrl: _callSnapshot.remoteAvatarUrl,
        error: _callSnapshot.error,
      ),
    );
  }

  Future<void> setVideoMuted(bool muted) async {
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getVideoTracks()) {
        track.enabled = !muted;
      }
    }
    _publishSnapshot(
      ChatCallSnapshot(
        phase: _callSnapshot.phase,
        isVideo: _callSnapshot.isVideo,
        isIncoming: _callSnapshot.isIncoming,
        microphoneMuted: _callSnapshot.microphoneMuted,
        videoMuted: muted,
        speakerOn: _callSnapshot.speakerOn,
        remoteUserId: _callSnapshot.remoteUserId,
        remoteDisplayName: _callSnapshot.remoteDisplayName,
        remoteAvatarUrl: _callSnapshot.remoteAvatarUrl,
        error: _callSnapshot.error,
      ),
    );
  }

  Future<void> setSpeakerOn(bool speakerOn) async {
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
    } catch (_) {
      // Some platforms may not expose explicit speakerphone routing.
    }
    _publishSnapshot(
      ChatCallSnapshot(
        phase: _callSnapshot.phase,
        isVideo: _callSnapshot.isVideo,
        isIncoming: _callSnapshot.isIncoming,
        microphoneMuted: _callSnapshot.microphoneMuted,
        videoMuted: _callSnapshot.videoMuted,
        speakerOn: speakerOn,
        remoteUserId: _callSnapshot.remoteUserId,
        remoteDisplayName: _callSnapshot.remoteDisplayName,
        remoteAvatarUrl: _callSnapshot.remoteAvatarUrl,
        error: _callSnapshot.error,
      ),
    );
  }

  void resetCallState() {
    unawaited(_endCallSession(clearSnapshot: true));
  }

  Future<void> _endCallSession({
    required bool clearSnapshot,
    bool promoteQueuedIncoming = false,
    ChatCallSnapshot? snapshot,
  }) async {
    _cancelIncomingRingTimeout();
    _cancelOutgoingRingTimeout();
    _cancelConnectingTimeout();

    _incomingCallId = null;
    _incomingCallRoomId = null;
    _incomingOfferSdp = null;
    _incomingCallerUserId = null;
    _incomingCallerDisplayName = null;
    _activeCallId = null;
    _activeCallRoomId = null;
    _activeCallIsIncoming = false;
    _pendingRemoteCandidates.clear();

    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      await stream.dispose();
    }

    final localRenderer = _localVideoRenderer;
    if (localRenderer != null) {
      localRenderer.srcObject = null;
    }
    final remoteRenderer = _remoteVideoRenderer;
    if (remoteRenderer != null) {
      remoteRenderer.srcObject = null;
    }
    _emitCallMediaUpdate();

    final peer = _peerConnection;
    _peerConnection = null;
    if (peer != null) {
      await peer.close();
      await peer.dispose();
    }

    if (clearSnapshot) {
      _publishSnapshot(const ChatCallSnapshot.idle());
    } else if (snapshot != null) {
      _publishSnapshot(snapshot);
    }

    if (promoteQueuedIncoming) {
      _promoteQueuedIncomingCall();
    }
  }

  String _nextCallId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random.secure().nextInt(1 << 31);
    return '${ts}_$rand';
  }

  Future<void> _ensurePeerConnection({
    required String roomId,
    required String callId,
    required bool isVideo,
  }) async {
    if (_peerConnection != null) {
      return;
    }

    MatrixTurnServerInfo turn;
    try {
      turn = await _resolveTurnServerInfoOrThrow();
    } catch (e) {
      throw StateError(_turnFailureMessage(e));
    }

    final iceServers = <Map<String, dynamic>>[
      <String, dynamic>{
        'urls': <String>['stun:stun.l.google.com:19302'],
      },
      if (turn.isUsable)
        <String, dynamic>{
          'urls': turn.uris,
          'username': turn.username,
          'credential': turn.password,
        },
    ];
    final config = <String, dynamic>{'iceServers': iceServers};

    final peer = await createPeerConnection(config);
    _peerConnection = peer;
    _activeCallId = callId;
    _activeCallRoomId = roomId;
    _activeCallIsVideo = isVideo;

    peer.onIceCandidate = (candidate) {
      final activeRoom = _activeCallRoomId;
      final activeCall = _activeCallId;
      final candidateValue = candidate.candidate;
      if (activeRoom == null ||
          activeCall == null ||
          candidateValue == null ||
          candidateValue.isEmpty) {
        return;
      }
      unawaited(
        sendCallCandidatesSignal(
          roomId: activeRoom,
          callId: activeCall,
          candidates: <Map<String, dynamic>>[
            <String, dynamic>{
              'candidate': candidateValue,
              if ((candidate.sdpMid ?? '').isNotEmpty)
                'sdpMid': candidate.sdpMid,
              if (candidate.sdpMLineIndex != null)
                'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          ],
        ),
      );
    };

    peer.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _cancelOutgoingRingTimeout();
        _cancelIncomingRingTimeout();
        _cancelConnectingTimeout();
        _publishSnapshot(
          ChatCallSnapshot(
            phase: ChatCallPhase.connected,
            isVideo: _callSnapshot.isVideo,
            isIncoming: _callSnapshot.isIncoming,
            microphoneMuted: _callSnapshot.microphoneMuted,
            videoMuted: _callSnapshot.videoMuted,
            speakerOn: _callSnapshot.speakerOn,
            remoteUserId: _callSnapshot.remoteUserId,
            remoteDisplayName: _callSnapshot.remoteDisplayName,
            remoteAvatarUrl: _callSnapshot.remoteAvatarUrl,
          ),
        );
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(
          _endCallSession(
            clearSnapshot: false,
            promoteQueuedIncoming: true,
            snapshot: ChatCallSnapshot(
              phase: ChatCallPhase.ended,
              isVideo: _callSnapshot.isVideo,
              isIncoming: _callSnapshot.isIncoming,
              microphoneMuted: false,
              videoMuted: false,
              speakerOn: false,
              remoteUserId: _callSnapshot.remoteUserId,
              remoteDisplayName: _callSnapshot.remoteDisplayName,
              remoteAvatarUrl: _callSnapshot.remoteAvatarUrl,
            ),
          ),
        );
      }
    };

    peer.onTrack = (event) {
      final remote = _remoteVideoRenderer;
      if (remote != null && event.streams.isNotEmpty) {
        remote.srcObject = event.streams.first;
        _emitCallMediaUpdate();
      }
    };

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': isVideo
          ? <String, dynamic>{
              'facingMode': 'user',
              'width': <String, dynamic>{'ideal': 640},
              'height': <String, dynamic>{'ideal': 480},
            }
          : false,
    };
    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localStream = stream;
    final local = _localVideoRenderer;
    if (local != null) {
      local.srcObject = stream;
      _emitCallMediaUpdate();
    }
    for (final track in stream.getTracks()) {
      await peer.addTrack(track, stream);
    }
  }

  Future<void> _ensureVideoRenderers() async {
    if (_localVideoRenderer == null) {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _localVideoRenderer = renderer;
    }
    if (_remoteVideoRenderer == null) {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _remoteVideoRenderer = renderer;
    }
  }

  Future<MatrixTurnServerInfo> _resolveTurnServerInfoOrThrow() async {
    final turn = await _core.getTurnServerConfig();
    final info = MatrixTurnServerInfo(
      uris: turn.uris,
      username: turn.username,
      password: turn.password,
      ttl: turn.ttl,
    );
    if (!info.isUsable) {
      throw StateError('TURN server returned incomplete credentials.');
    }
    return info;
  }

  String _turnFailureMessage(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('401') || lower.contains('403')) {
      return 'TURN auth failed (401/403). Check Matrix /voip/turnServer auth and token validity.';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'TURN lookup failed due to network connectivity issues.';
    }
    return 'TURN configuration failed: $raw';
  }

  String _collisionMessage() {
    final queueLength = _incomingCallQueue.length;
    if (queueLength <= 0) {
      return 'Another call is already active. End it before starting a new one.';
    }
    return 'Another call is active, and $queueLength incoming call(s) are queued.';
  }

  void _armIncomingRingTimeout({
    required String roomId,
    required String callId,
  }) {
    _cancelIncomingRingTimeout();
    _incomingRingTimer = Timer(_incomingRingTimeout, () {
      if (_incomingCallId != callId || _incomingCallRoomId != roomId) {
        return;
      }
      unawaited(sendCallRejectSignal(roomId: roomId, callId: callId));
      unawaited(
        _endCallSession(
          clearSnapshot: false,
          promoteQueuedIncoming: true,
          snapshot: ChatCallSnapshot(
            phase: ChatCallPhase.error,
            isVideo: _activeCallIsVideo,
            isIncoming: true,
            microphoneMuted: false,
            videoMuted: false,
            speakerOn: false,
            remoteUserId: _incomingCallerUserId,
            remoteDisplayName: _incomingCallerDisplayName,
            error: 'Incoming call timed out.',
          ),
        ),
      );
    });
  }

  void _armOutgoingRingTimeout({
    required String roomId,
    required String callId,
    required bool isVideo,
  }) {
    _cancelOutgoingRingTimeout();
    _outgoingRingTimer = Timer(_outgoingRingTimeout, () {
      if (_activeCallId != callId || _activeCallRoomId != roomId) {
        return;
      }
      unawaited(sendCallHangupSignal(roomId: roomId, callId: callId));
      unawaited(
        _endCallSession(
          clearSnapshot: false,
          promoteQueuedIncoming: true,
          snapshot: ChatCallSnapshot(
            phase: ChatCallPhase.error,
            isVideo: isVideo,
            isIncoming: false,
            microphoneMuted: false,
            videoMuted: false,
            speakerOn: false,
            error: 'No answer from remote party (ring timeout).',
          ),
        ),
      );
    });
  }

  void _armConnectingTimeout() {
    _cancelConnectingTimeout();
    _connectingTimer = Timer(_connectingTimeout, () {
      if (_callSnapshot.phase == ChatCallPhase.connected) {
        return;
      }
      unawaited(
        _endCallSession(
          clearSnapshot: false,
          promoteQueuedIncoming: true,
          snapshot: ChatCallSnapshot(
            phase: ChatCallPhase.error,
            isVideo: _activeCallIsVideo,
            isIncoming: _activeCallIsIncoming,
            microphoneMuted: false,
            videoMuted: false,
            speakerOn: false,
            remoteUserId: _callSnapshot.remoteUserId,
            remoteDisplayName: _callSnapshot.remoteDisplayName,
            error: 'Call connection timed out.',
          ),
        ),
      );
    });
  }

  void _cancelIncomingRingTimeout() {
    _incomingRingTimer?.cancel();
    _incomingRingTimer = null;
  }

  void _cancelOutgoingRingTimeout() {
    _outgoingRingTimer?.cancel();
    _outgoingRingTimer = null;
  }

  void _cancelConnectingTimeout() {
    _connectingTimer?.cancel();
    _connectingTimer = null;
  }

  void _emitCallMediaUpdate() {
    if (!_callMediaUpdates.isClosed) {
      _callMediaUpdates.add(null);
    }
  }

  void _promoteQueuedIncomingCall() {
    if (_activeCallId != null || _incomingCallQueue.isEmpty) {
      return;
    }
    final next = _incomingCallQueue.removeAt(0);
    _activeCallId = next.callId;
    _activeCallRoomId = next.roomId;
    _activeCallIsVideo = next.isVideo;
    _activeCallIsIncoming = true;
    _incomingCallId = next.callId;
    _incomingCallRoomId = next.roomId;
    _incomingOfferSdp = next.offerSdp;
    _incomingCallerUserId = next.senderId;
    _incomingCallerDisplayName = next.senderDisplayName;
    _pendingRemoteCandidates.clear();

    _armIncomingRingTimeout(roomId: next.roomId, callId: next.callId);
    _publishSnapshot(
      ChatCallSnapshot(
        phase: ChatCallPhase.ringing,
        isVideo: next.isVideo,
        isIncoming: true,
        microphoneMuted: false,
        videoMuted: false,
        speakerOn: false,
        remoteUserId: next.senderId,
        remoteDisplayName: next.senderDisplayName,
      ),
    );
  }

  Future<void> _drainPendingRemoteCandidates() async {
    final peer = _peerConnection;
    if (peer == null || _pendingRemoteCandidates.isEmpty) {
      return;
    }
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      await peer.addCandidate(candidate);
    }
  }

  Future<String> createDirectMessage({required String otherUserId}) async {
    await initialize();
    return _core.createRoom(
      name: '',
      invite: <String>[otherUserId],
      isDirect: true,
      initialState: <Map<String, dynamic>>[_encryptedRoomStateEvent()],
    );
  }

  Future<String> createGroup({
    required String name,
    required List<String> userIds,
    List<int>? avatarBytes,
    String? avatarFilename,
    String? avatarMimeType,
  }) async {
    await initialize();
    final current = (currentUserId ?? '').trim();
    final sanitizedInvitees = userIds
        .map((userId) => userId.trim())
        .where((userId) => userId.isNotEmpty && userId != current)
        .toSet()
        .toList(growable: false);
    final initialState = <Map<String, dynamic>>[_encryptedRoomStateEvent()];
    if (avatarBytes != null &&
        avatarBytes.isNotEmpty &&
        (avatarFilename ?? '').trim().isNotEmpty) {
      final mxc = await _core.uploadMedia(
        bytes: avatarBytes,
        filename: avatarFilename!,
        mimeType: avatarMimeType ?? _mimeTypeFromFileName(avatarFilename),
      );
      if (mxc.trim().isNotEmpty) {
        initialState.add(<String, dynamic>{
          'type': 'm.room.avatar',
          'state_key': '',
          'content': <String, dynamic>{'url': mxc},
        });
      }
    }
    return _core.createRoom(
      name: name,
      invite: sanitizedInvitees,
      isDirect: false,
      initialState: initialState,
    );
  }

  Map<String, dynamic> _encryptedRoomStateEvent() {
    return <String, dynamic>{
      'type': 'm.room.encryption',
      'state_key': '',
      'content': const <String, dynamic>{'algorithm': 'm.megolm.v1.aes-sha2'},
    };
  }

  Future<String?> updateRoomAvatar({
    required String roomId,
    required List<int> bytes,
    required String filename,
    String? mimeType,
  }) async {
    await initialize();
    if (bytes.isEmpty || filename.trim().isEmpty) {
      return null;
    }

    final mxc = await _core.uploadMedia(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType ?? _mimeTypeFromFileName(filename),
    );
    if (mxc.trim().isEmpty) {
      return null;
    }

    await _core.setRoomAvatar(roomId, mxc);
    final avatarUrl = _mxcToThumbnailHttp(mxc);
    _updateCachedThreadAvatar(roomId, avatarUrl);
    return avatarUrl;
  }

  Future<ChatEncryptionStatus> getRoomEncryptionStatus(String roomId) async {
    await initialize();
    final stateEvents = await _core.getStateEvents(roomId);
    return _roomEncryptionStatus(stateEvents);
  }

  Future<void> registerPushToken({
    required String pushToken,
    required String gatewayUrl,
    required String appId,
    required String appDisplayName,
    required String deviceDisplayName,
    String lang = 'en',
    String profileTag = 'mobile',
  }) async {
    await initialize();
    await _core.setHttpPusher(
      pushKey: pushToken,
      appId: appId,
      appDisplayName: appDisplayName,
      deviceDisplayName: deviceDisplayName,
      url: gatewayUrl,
      lang: lang,
      profileTag: profileTag,
    );
  }

  Future<void> unregisterPushToken({
    required String pushToken,
    required String appId,
  }) async {
    await initialize();
    await _core.deletePusher(pushKey: pushToken, appId: appId);
  }

  Future<List<ChatParticipant>> getRoomParticipants(
    String roomId, {
    bool forceRefresh = false,
  }) async {
    await initialize();

    final cachedAt = _participantsCacheAt[roomId];
    if (!forceRefresh && cachedAt != null) {
      final age = DateTime.now().difference(cachedAt);
      if (age <= _participantsCacheTtl &&
          _participantsCache.containsKey(roomId)) {
        return _participantsCache[roomId]!;
      }
    }

    final members = await _core.getMembers(roomId);
    final chunk = _asList(members['chunk']);

    final out = <ChatParticipant>[];
    for (final entry in chunk) {
      final event = _asMap(entry);
      final stateKey = (event['state_key'] ?? '').toString();
      if (stateKey.isEmpty) continue;

      final content = _asMap(event['content']);
      final membership = (content['membership'] ?? '').toString();
      if (membership != 'join' && membership != 'invite') continue;

      final displayNameRaw = (content['displayname'] ?? '').toString().trim();
      out.add(
        ChatParticipant(
          userId: stateKey,
          displayName: displayNameRaw.isEmpty ? stateKey : displayNameRaw,
          level: ChatMemberLevel.member,
          membership: membership,
          avatarUrl: _mxcToThumbnailHttp(content['avatar_url']),
        ),
      );
    }

    out.sort((a, b) => a.displayName.compareTo(b.displayName));
    _participantsCache[roomId] = out;
    _participantsCacheAt[roomId] = DateTime.now();
    _userSearchCache.clear();
    unawaited(_persistCache());
    return out;
  }

  Future<List<ChatParticipant>> searchUsers(
    String query, {
    int maxResults = 25,
    String? excludeUserId,
  }) async {
    await initialize();
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const <ChatParticipant>[];

    final cacheKey = '${excludeUserId ?? ''}|$trimmed|$maxResults';
    final cached = _userSearchCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final threads = _cachedThreads.isNotEmpty
        ? List<ChatThread>.from(_cachedThreads)
        : await getJoinedThreads();
    final byUser = <String, ChatParticipant>{};
    var missingCachedParticipants = false;

    void addMatches(Iterable<ChatParticipant> participants) {
      for (final participant in participants) {
        final userId = participant.userId.toLowerCase();
        final display = participant.displayName.toLowerCase();
        if (!userId.contains(trimmed) && !display.contains(trimmed)) {
          continue;
        }
        if (excludeUserId != null && participant.userId == excludeUserId) {
          continue;
        }
        byUser.putIfAbsent(participant.userId, () => participant);
        if (byUser.length >= maxResults) {
          return;
        }
      }
    }

    for (final thread in threads) {
      final participants = _participantsCache[thread.id];
      if (participants == null) {
        missingCachedParticipants = true;
        continue;
      }
      addMatches(participants);
      if (byUser.length >= maxResults) break;
    }

    if (byUser.length < maxResults && missingCachedParticipants) {
      for (final thread in threads) {
        if (_participantsCache.containsKey(thread.id)) {
          continue;
        }
        final participants = await getRoomParticipants(thread.id);
        addMatches(participants);
        if (byUser.length >= maxResults) break;
      }
    }

    final results = byUser.values.take(maxResults).toList(growable: false);
    _userSearchCache[cacheKey] = results;
    return results;
  }

  Future<ChatUserPresence> getUserPresence(
    String userId, {
    bool forceRefresh = false,
  }) async {
    await initialize();
    final cached = _presenceCache[userId];
    final cachedAt = _presenceCacheAt[userId];
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(seconds: 45)) {
      return cached;
    }

    try {
      final result = await _core.getPresenceStatus(userId);
      final presence = (result['presence'] ?? 'offline').toString();
      final currentlyActive = result['currently_active'] == true;
      final lastActiveAgo = result['last_active_ago'];
      DateTime? lastActiveAt;
      if (lastActiveAgo is num && lastActiveAgo >= 0) {
        lastActiveAt = DateTime.now().subtract(
          Duration(milliseconds: lastActiveAgo.round()),
        );
      }

      final parsed = ChatUserPresence(
        userId: userId,
        isOnline: currentlyActive || presence == 'online',
        lastActiveAt: lastActiveAt,
        presence: presence,
      );
      _presenceCache[userId] = parsed;
      _presenceCacheAt[userId] = DateTime.now();
      return parsed;
    } catch (_) {
      final fallback = ChatUserPresence(userId: userId, isOnline: false);
      _presenceCache[userId] = fallback;
      _presenceCacheAt[userId] = DateTime.now();
      return fallback;
    }
  }

  ChatUserPresence? cachedUserPresence(String userId) {
    final cached = _presenceCache[userId];
    final cachedAt = _presenceCacheAt[userId];
    if (cached == null || cachedAt == null) {
      return null;
    }
    if (DateTime.now().difference(cachedAt) >= const Duration(seconds: 45)) {
      return null;
    }
    return cached;
  }

  ChatParticipant? cachedDirectMessageCounterpart(String roomId) {
    return _directMessageCounterpartForRoom(roomId, const <dynamic>[]);
  }

  Future<String?> startKeyVerification({
    required String userId,
    String? roomId,
  }) async {
    await initialize();
    try {
      return await _core.startVerification(userId: userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> acceptVerification(String verificationId) async {
    await initialize();
    try {
      await _core.acceptVerification(verificationId);
    } catch (_) {
      // Silently fail if verification session not found or backend unavailable.
    }
  }

  Future<void> rejectVerification(String verificationId) async {
    await initialize();
    try {
      await _core.rejectVerification(verificationId);
    } catch (_) {
      // Silently fail if verification session not found.
    }
  }

  Future<void> acceptSas(String verificationId) async {
    await initialize();
    try {
      await _core.acceptSas(verificationId);
    } catch (_) {
      // Silently fail.
    }
  }

  Future<void> rejectSas(String verificationId) async {
    await initialize();
    try {
      await _core.rejectSas(verificationId);
    } catch (_) {
      // Silently fail.
    }
  }

  List<VerificationSession> getVerificationSessions() {
    if (!_initialized) return const <VerificationSession>[];

    final sessions = _core.getVerificationSessions();
    return sessions
        .map(
          (session) => VerificationSession(
            id: (session['id'] ?? '').toString(),
            userId: (session['userId'] ?? '').toString(),
            state: (session['state'] ?? 'pending').toString(),
            isDone: session['isDone'] == true,
          ),
        )
        .toList(growable: false);
  }

  Future<void> dispose() async {
    _stopSyncLoop();
    await _endCallSession(clearSnapshot: true);

    final localRenderer = _localVideoRenderer;
    _localVideoRenderer = null;
    if (localRenderer != null) {
      await localRenderer.dispose();
    }
    final remoteRenderer = _remoteVideoRenderer;
    _remoteVideoRenderer = null;
    if (remoteRenderer != null) {
      await remoteRenderer.dispose();
    }

    if (_initialized) {
      _core.dispose();
    }
    await _syncUpdates.close();
    await _callUpdates.close();
    await _callMediaUpdates.close();
  }

  void _startSyncLoop() {
    _stopSyncLoop();
    final generation = ++_syncLoopGeneration;
    unawaited(_runSyncLoop(generation));
  }

  void _stopSyncLoop() {
    _syncLoopGeneration++;
  }

  Future<void> _runSyncLoop(int generation) async {
    while (generation == _syncLoopGeneration &&
        _initialized &&
        _core.isLoggedIn) {
      final succeeded = await _refreshSync(
        fullState: false,
        timeoutMs: _syncLongPollTimeoutMs,
      );
      if (generation != _syncLoopGeneration ||
          !_initialized ||
          !_core.isLoggedIn) {
        break;
      }
      if (!succeeded) {
        await Future<void>.delayed(_syncRetryDelay);
      }
    }
  }

  Future<bool> _refreshSync({
    required bool fullState,
    int timeoutMs = 0,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final sync = await _core.sync(timeoutMs: timeoutMs, fullState: fullState);
      final rooms = _asMap(sync['rooms']);
      final joined = _asMap(rooms['join']);
      final invited = _asMap(rooms['invite']);
      var timelineEvents = 0;
      for (final roomEntry in joined.entries) {
        final roomData = _asMap(roomEntry.value);
        final timelineEnvelope = _asMap(roomData['timeline']);
        timelineEvents += _asList(timelineEnvelope['events']).length;
      }
      final hasRoomDelta = joined.isNotEmpty || invited.isNotEmpty;
      final hasTimelineDelta = timelineEvents > 0;
      _captureTyping(sync);
      _captureCallSignaling(sync);
      // Update the cache for any sync that has room data (joined/invited),
      // even when there are zero timeline events. Synapse sends unread_notifications
      // count changes (read receipts, push rule updates) inside joined rooms with
      // no timeline events — we still need to apply those to update badge counts.
      if (fullState || hasRoomDelta) {
        _applyThreadSyncDelta(joined: joined, invited: invited);
      }
      if (fullState || hasRoomDelta || hasTimelineDelta) {
        await _persistCache();
      }
      _perfLog('_refreshSync', stopwatch, <String, Object?>{
        'fullState': fullState,
        'joinedRooms': joined.length,
        'invitedRooms': invited.length,
        'timelineEvents': timelineEvents,
      });
      if (fullState || hasRoomDelta || hasTimelineDelta) {
        _emitSyncUpdate();
      }
      return true;
    } catch (_) {
      _perfLog('_refreshSync.error', stopwatch, <String, Object?>{
        'fullState': fullState,
      }, true);
      // Keep the sync loop resilient to transient network issues.
      return false;
    }
  }

  void _scheduleRoomMessagesRefresh({
    required String roomId,
    required int limit,
  }) {
    final lastRefresh = _roomMessageRefreshAt[roomId];
    if (lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < _roomMessageRefreshCooldown) {
      return;
    }
    if (_roomMessageRefreshInFlight.contains(roomId)) {
      return;
    }

    _roomMessageRefreshInFlight.add(roomId);
    _roomMessageRefreshAt[roomId] = DateTime.now();
    unawaited(() async {
      try {
        await getRoomMessages(roomId, limit: limit, allowCache: false);
        _emitSyncUpdate();
      } catch (_) {
        // Background refresh is best-effort.
      } finally {
        _roomMessageRefreshInFlight.remove(roomId);
      }
    }());
  }

  Future<void> _hydrateCache(String userId) async {
    try {
      final snapshot = await _cacheStore.load(
        databaseName: databaseName,
        userId: userId,
      );
      if (snapshot == null) {
        _cachedThreads = const <ChatThread>[];
        _cachedMessagesByRoom.clear();
        return;
      }
      _cachedThreads = snapshot.threads;
      _participantsCache
        ..clear()
        ..addAll(snapshot.participantsByRoom);
      _participantsCacheAt
        ..clear()
        ..addEntries(
          snapshot.participantsByRoom.keys.map(
            (roomId) => MapEntry(roomId, DateTime.now()),
          ),
        );
      _userSearchCache.clear();
      _cachedMessagesByRoom
        ..clear()
        ..addAll(snapshot.messagesByRoom);
      _typingUsersByRoom
        ..clear()
        ..addAll(snapshot.typingUsersByRoom);
      _readReceiptsByRoomEvent
        ..clear()
        ..addAll(snapshot.readReceiptsByRoomEvent);
      _core.restoreSinceToken(snapshot.sinceToken);
      _lastMessageSenderByRoom
        ..clear()
        ..addAll(snapshot.lastMessageSenderByRoom);
      _lastMessagePreviewByRoom
        ..clear()
        ..addAll(snapshot.lastMessagePreviewByRoom);

      // Fix "You:" prefix: scan persisted messages to detect own last messages.
      // This handles the case where no new sync event arrives for a room, so
      // the cached thread lastMessage still shows "DisplayName: body" instead
      // of "You: body".
      final fixedThreads = <ChatThread>[];
      for (final thread in _cachedThreads) {
        final msgs = _cachedMessagesByRoom[thread.id];
        final lm = (thread.lastMessage ?? '').trim();
        if (msgs != null && msgs.isNotEmpty && lm.isNotEmpty) {
          final lastMsg = msgs.reduce(
            (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
          );
          final isMe = lastMsg.senderId.trim() == userId;
          if (isMe && !lm.startsWith('You: ')) {
            final colonIdx = lm.indexOf(': ');
            final fixed = colonIdx > 0
                ? 'You: ${lm.substring(colonIdx + 2)}'
                : 'You: $lm';
            fixedThreads.add(thread.copyWith(lastMessage: fixed));
            continue;
          }
        }
        fixedThreads.add(thread);
      }
      _cachedThreads = fixedThreads;
      final hydratedCallSnapshot = _chatCallSnapshotFromMap(
        snapshot.callSnapshot,
      );
      if (hydratedCallSnapshot != null) {
        _callSnapshot = hydratedCallSnapshot;
      }
      _perfLog('cache.hydrate', Stopwatch()..start(), <String, Object?>{
        'rooms': _cachedThreads.length,
        'roomsWithParticipants': _participantsCache.length,
        'roomsWithMessages': _cachedMessagesByRoom.length,
        'roomsWithTyping': _typingUsersByRoom.length,
        'roomsWithReceipts': _readReceiptsByRoomEvent.length,
        'hasSinceToken': (snapshot.sinceToken ?? '').isNotEmpty,
      }, true);
    } catch (_) {
      _cachedThreads = const <ChatThread>[];
      _participantsCache.clear();
      _participantsCacheAt.clear();
      _userSearchCache.clear();
      _cachedMessagesByRoom.clear();
      _typingUsersByRoom.clear();
      _readReceiptsByRoomEvent.clear();
    }
  }

  Future<void> _persistCache() async {
    final userId = (_cachedUserId ?? _core.currentUserId ?? '').trim();
    if (userId.isEmpty) {
      return;
    }
    try {
      await _cacheStore.save(
        databaseName: databaseName,
        userId: userId,
        sinceToken: _core.sinceToken,
        threads: _cachedThreads,
        participantsByRoom: _participantsCache,
        messagesByRoom: _cachedMessagesByRoom,
        typingUsersByRoom: _typingUsersByRoom,
        readReceiptsByRoomEvent: _compactReadReceiptsForCache(
          _readReceiptsByRoomEvent,
        ),
        callSnapshot: _chatCallSnapshotToMap(_callSnapshot),
        lastMessageSenderByRoom: Map<String, String>.from(
          _lastMessageSenderByRoom,
        ),
        lastMessagePreviewByRoom: Map<String, String>.from(
          _lastMessagePreviewByRoom,
        ),
      );
    } catch (_) {
      // Cache writes are best-effort.
    }
  }

  List<ChatMessage> _mergeCachedRoomMessages({
    required List<ChatMessage> existing,
    required List<ChatMessage> incoming,
  }) {
    if (existing.isEmpty) {
      return List<ChatMessage>.from(incoming)
        ..sort(_compareMessagesForTimeline);
    }
    if (incoming.isEmpty) {
      return List<ChatMessage>.from(existing)
        ..sort(_compareMessagesForTimeline);
    }

    final byId = <String, ChatMessage>{};
    for (final message in existing) {
      if (message.id.isNotEmpty) {
        byId[message.id] = message;
      }
    }
    for (final message in incoming) {
      if (message.id.isEmpty) {
        continue;
      }
      byId[message.id] = message;
    }
    final merged = byId.values.toList(growable: false)
      ..sort(_compareMessagesForTimeline);
    return merged;
  }

  List<ChatMessage> _mergeFreshRoomMessages({
    required List<ChatMessage> existing,
    required List<ChatMessage> incoming,
  }) {
    if (incoming.isEmpty) {
      return List<ChatMessage>.from(existing)
        ..sort(_compareMessagesForTimeline);
    }

    // For network refreshes, server results are authoritative for the returned
    // window. Keep older cached messages outside that window to avoid
    // truncating room history on each refresh (limit-based fetches).
    final byId = <String, ChatMessage>{
      for (final message in incoming)
        if (message.id.isNotEmpty) message.id: message,
    };

    final oldestIncoming = incoming
        .map((message) => message.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    for (final message in existing) {
      final id = message.id;
      if (id.isEmpty) {
        continue;
      }

      final isLocalOptimistic = id.startsWith(_localMessagePrefix);
      final isOlderThanWindow = message.createdAt.isBefore(oldestIncoming);
      if (isLocalOptimistic || isOlderThanWindow) {
        byId.putIfAbsent(id, () => message);
      }
    }

    final merged = byId.values.toList(growable: false)
      ..sort(_compareMessagesForTimeline);
    return merged;
  }

  int _compareMessagesForTimeline(ChatMessage a, ChatMessage b) {
    final byDate = a.createdAt.compareTo(b.createdAt);
    if (byDate != 0) {
      return byDate;
    }
    return a.id.compareTo(b.id);
  }

  List<ChatThread> _mergeThreadDelta({
    required List<ChatThread> existing,
    required List<ChatThread> delta,
    required bool replaceAll,
  }) {
    if (replaceAll) {
      return List<ChatThread>.from(delta);
    }
    if (delta.isEmpty) {
      return List<ChatThread>.from(existing);
    }

    final byId = <String, ChatThread>{
      for (final thread in existing) thread.id: thread,
    };
    for (final thread in delta) {
      byId[thread.id] = thread;
    }
    final merged = byId.values.toList(growable: false)
      ..sort((a, b) {
        if (a.isInvited != b.isInvited) {
          return a.isInvited ? -1 : 1;
        }
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return merged;
  }

  /// Forces a full integrity check on all cached threads regardless of their
  /// current display state.  Rooms with incomplete data (missing title, missing
  /// last-message, stale avatars) are re-fetched from the server.  A full-state
  /// Matrix sync is run first so that rooms the client missed entirely are
  /// discovered and added to the cache before the per-room repair pass runs.
  ///
  /// Returns the number of threads that were repaired / added.
  Future<int> runFullIntegrityCheck({
    void Function(double progress, String status)? onProgress,
  }) async {
    await initialize();
    onProgress?.call(0.05, 'Syncing rooms from server…');

    // Full-state sync so we don't miss any rooms.
    final sync = await _core.sync(timeoutMs: 0, fullState: true);
    _captureTyping(sync);
    final roomsData = (sync['rooms'] as Map?) ?? const <String, dynamic>{};
    final joined = (roomsData['join'] as Map?) ?? const <String, dynamic>{};
    final invited = (roomsData['invite'] as Map?) ?? const <String, dynamic>{};

    // Ensure every room from the server is at least a skeleton thread in cache.
    final knownIds = _cachedThreads.map((t) => t.id).toSet();
    var newRooms = 0;
    for (final roomId in joined.keys) {
      if (!knownIds.contains(roomId)) {
        final stateEvents = _asList(
          ((_asMap(joined[roomId]))['state'] as Object?),
        );
        final title = _roomTitle(roomId.toString(), stateEvents);
        _cachedThreads = [
          ..._cachedThreads,
          ChatThread(
            id: roomId.toString(),
            title: title,
            updatedAt: DateTime.now(),
            lastMessage: '',
            unreadCount: 0,
            avatarUrl: _roomAvatarUrl(stateEvents),
            type: ChatType.group,
            isInvited: false,
          ),
        ];
        newRooms++;
      }
    }
    for (final roomId in invited.keys) {
      if (!knownIds.contains(roomId)) {
        _cachedThreads = [
          ..._cachedThreads,
          ChatThread(
            id: roomId.toString(),
            title: roomId.toString(),
            updatedAt: DateTime.now(),
            lastMessage: 'Invitation pending',
            unreadCount: 0,
            avatarUrl: null,
            type: ChatType.group,
            isInvited: true,
          ),
        ];
        newRooms++;
      }
    }

    onProgress?.call(0.25, 'Checking ${_cachedThreads.length} chats…');

    // Run per-room integrity repair on ALL threads (not just broken ones).
    final allIds = _cachedThreads.map((t) => t.id).toList(growable: false);
    final batchSize = 8;
    var repairedCount = newRooms;
    for (var i = 0; i < allIds.length; i += batchSize) {
      final batch = allIds.skip(i).take(batchSize).toList();
      final before = List<ChatThread>.from(_cachedThreads);

      // Temporarily remove from in-flight set so we can repair everything.
      _threadIntegrityRepairInFlight.removeAll(batch);
      _threadIntegrityRepairInFlight.addAll(batch);
      await _repairThreadIntegrity(batch);

      // Count how many threads changed.
      for (final id in batch) {
        final beforeThread = before.firstWhere(
          (t) => t.id == id,
          orElse: () => ChatThread(
            id: id,
            title: '',
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
            lastMessage: '',
            unreadCount: 0,
            avatarUrl: null,
            type: ChatType.group,
            isInvited: false,
          ),
        );
        final afterThread = _cachedThreadById(id);
        if (afterThread != null &&
            !_sameThreadDisplay(beforeThread, afterThread)) {
          repairedCount++;
        }
      }

      final done = (i + batch.length).clamp(0, allIds.length);
      onProgress?.call(
        0.25 + 0.70 * (done / allIds.length),
        'Checking chats… $done / ${allIds.length}',
      );
    }

    onProgress?.call(1.0, 'Done');
    return repairedCount;
  }

  void _scheduleThreadIntegrityRepair(
    Iterable<ChatThread> threads, {
    bool forceAll = false,
  }) {
    final candidateThreads = forceAll
        ? threads
        : threads.where(_needsThreadIntegrityRepair);
    final roomIds = candidateThreads
        .map((thread) => thread.id)
        .where((roomId) => !_threadIntegrityRepairInFlight.contains(roomId))
        .take(forceAll ? 24 : 8)
        .toList(growable: false);
    if (roomIds.isEmpty) {
      return;
    }

    _threadIntegrityRepairInFlight.addAll(roomIds);
    unawaited(_repairThreadIntegrity(roomIds));
  }

  bool _needsThreadIntegrityRepair(ChatThread thread) {
    if (thread.isInvited) {
      return false;
    }
    if (!_hasUsefulThreadTitle(thread.title, thread.id)) {
      return true;
    }
    final lastMessage = (thread.lastMessage ?? '').trim();
    return lastMessage.isEmpty;
  }

  Future<void> _repairThreadIntegrity(List<String> roomIds) async {
    try {
      await initialize();
      var changed = false;
      var repairedMessages = false;
      final mutable = List<ChatThread>.from(_cachedThreads);

      for (final roomId in roomIds) {
        try {
          final index = mutable.indexWhere((thread) => thread.id == roomId);
          if (index < 0) {
            continue;
          }

          final existing = mutable[index];
          final repaired = await _repairThreadIntegrityFromServer(existing);
          final threadChanged = !_sameThreadDisplay(existing, repaired);
          if (threadChanged) {
            mutable[index] = repaired;
            changed = true;
            // Only refresh cached messages when the thread metadata itself
            // changed — avoids re-fetching messages for every room on startup.
            final cachedMessages = _cachedMessagesByRoom[roomId];
            if (cachedMessages != null && cachedMessages.isNotEmpty) {
              await getRoomMessages(
                roomId,
                limit: max(60, min(cachedMessages.length, 120)),
                allowCache: false,
              );
              repairedMessages = true;
            }
          }
        } catch (_) {
          // Integrity repair is best-effort.
        } finally {
          _threadIntegrityRepairInFlight.remove(roomId);
        }
      }

      if (!changed) {
        if (repairedMessages) {
          _emitSyncUpdate();
        }
        return;
      }

      mutable.sort((a, b) {
        if (a.isInvited != b.isInvited) {
          return a.isInvited ? -1 : 1;
        }
        return b.updatedAt.compareTo(a.updatedAt);
      });
      _cachedThreads = mutable;
      await _persistCache();
      _emitSyncUpdate();
    } finally {
      _threadIntegrityRepairInFlight.removeAll(roomIds);
    }
  }

  Future<ChatThread> _repairThreadIntegrityFromServer(
    ChatThread existing,
  ) async {
    var stateEvents = await _loadRoomStateEvents(existing.id);
    String title = existing.title;
    String? avatarUrl = existing.avatarUrl;
    var type = existing.type;

    if (stateEvents.isNotEmpty) {
      _cacheParticipantsFromStateEvents(existing.id, stateEvents);
      final resolvedTitle = _roomTitle(existing.id, stateEvents);
      final resolvedAvatar = _roomAvatarUrl(stateEvents);
      final isDm = _isLikelyDm(stateEvents);
      type = isDm ? ChatType.dm : ChatType.group;
      if (isDm) {
        final counterpart = _directMessageCounterpartForRoom(
          existing.id,
          stateEvents,
        );
        if (counterpart != null) {
          final counterpartName = counterpart.displayName.trim();
          if (_hasUsefulThreadTitle(counterpartName, existing.id)) {
            title = counterpartName;
          }
          avatarUrl = counterpart.avatarUrl ?? resolvedAvatar ?? avatarUrl;
        } else {
          if (_hasUsefulThreadTitle(resolvedTitle, existing.id)) {
            title = resolvedTitle;
          }
          avatarUrl = resolvedAvatar ?? avatarUrl;
        }
      } else {
        if (_hasUsefulThreadTitle(resolvedTitle, existing.id)) {
          title = resolvedTitle;
        }
        avatarUrl = resolvedAvatar ?? avatarUrl;
      }
    }

    var updatedAt = existing.updatedAt;
    var lastMessage = existing.lastMessage;
    final needsLatestMessage = (existing.lastMessage ?? '').trim().isEmpty;
    if (needsLatestMessage || !_hasUsefulThreadTitle(title, existing.id)) {
      final latestEvent = await _loadLatestMessageEvent(existing.id);
      if (latestEvent != null) {
        updatedAt = _roomEventDate(latestEvent, stateEvents);
        final senderName = _eventSenderLabel(latestEvent, stateEvents);
        final previewBody = _displayBodyFromEvent(latestEvent);
        final latestEventSenderId = (latestEvent['sender'] ?? '').toString();
        final latestIsMe =
            latestEventSenderId.isNotEmpty &&
            latestEventSenderId == (currentUserId ?? '');
        lastMessage = _formatThreadPreview(
          senderName: senderName,
          body: previewBody,
          isMe: latestIsMe,
        );
        _lastMessageTimeByRoom[existing.id] = updatedAt;
        _lastMessageSenderByRoom[existing.id] = latestIsMe ? 'me' : senderName;
        _lastMessageSenderIdByRoom[existing.id] = latestEventSenderId;
        _lastMessagePreviewByRoom[existing.id] = previewBody;
      }
    }

    return existing.copyWith(
      title: title,
      avatarUrl: avatarUrl,
      type: type,
      updatedAt: updatedAt,
      lastMessage: lastMessage,
    );
  }

  bool _sameThreadDisplay(ChatThread left, ChatThread right) {
    return left.title == right.title &&
        left.lastMessage == right.lastMessage &&
        left.avatarUrl == right.avatarUrl &&
        left.type == right.type &&
        left.updatedAt == right.updatedAt;
  }

  void _updateLocalThreadPreviewAfterSend({
    required String roomId,
    required String previewBody,
    required DateTime createdAt,
  }) {
    _lastMessagePreviewByRoom[roomId] = previewBody;
    _lastMessageSenderByRoom[roomId] = 'me';
    _lastMessageSenderIdByRoom[roomId] = currentUserId ?? '';
    _lastMessageTimeByRoom[roomId] = createdAt;

    final threadIndex = _cachedThreads.indexWhere(
      (thread) => thread.id == roomId,
    );
    if (threadIndex < 0) {
      return;
    }

    final updatedThread = _cachedThreads[threadIndex].copyWith(
      updatedAt: createdAt,
      lastMessage: _formatThreadPreview(
        senderName: '',
        body: previewBody,
        isMe: true,
      ),
    );
    final mutable = List<ChatThread>.from(_cachedThreads);
    mutable[threadIndex] = updatedThread;
    mutable.sort((a, b) {
      if (a.isInvited != b.isInvited) {
        return a.isInvited ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    _cachedThreads = mutable;
  }

  void _appendOptimisticCachedMessage({
    required String roomId,
    required ChatMessage message,
  }) {
    _cachedMessagesByRoom[roomId] = _mergeCachedRoomMessages(
      existing: _cachedMessagesByRoom[roomId] ?? const <ChatMessage>[],
      incoming: <ChatMessage>[message],
    );
  }

  void _replaceCachedMessage({
    required String roomId,
    required String previousId,
    required ChatMessage replacement,
  }) {
    final existing = (_cachedMessagesByRoom[roomId] ?? const <ChatMessage>[])
        .where((message) => message.id != previousId)
        .toList(growable: false);
    _cachedMessagesByRoom[roomId] = _mergeCachedRoomMessages(
      existing: existing,
      incoming: <ChatMessage>[replacement],
    );
  }

  void _captureCallSignaling(Map<String, dynamic> sync) {
    final rooms = _asMap(sync['rooms']);
    final join = _asMap(rooms['join']);
    final myUserId = currentUserId ?? '';

    for (final roomEntry in join.entries) {
      final roomId = roomEntry.key.toString();
      final roomData = _asMap(roomEntry.value);
      final timelineEnvelope = _asMap(roomData['timeline']);
      final timelineEvents = _asList(timelineEnvelope['events']);

      for (final raw in timelineEvents) {
        final event = _asMap(raw);
        final eventType = (event['type'] ?? '').toString();
        if (!eventType.startsWith('m.call.')) {
          continue;
        }

        final eventId = (event['event_id'] ?? '').toString();
        if (eventId.isNotEmpty && _seenCallEventIds.contains(eventId)) {
          continue;
        }
        if (eventId.isNotEmpty) {
          _seenCallEventIds.add(eventId);
        }

        final senderId = (event['sender'] ?? '').toString();
        if (senderId == myUserId) {
          continue;
        }

        final content = _asMap(event['content']);
        final callId = (content['call_id'] ?? '').toString();
        final isVideo = _isVideoCallContent(content);
        final remoteDisplayName = _displayNameForRoomUser(roomId, senderId);

        if (eventType == 'm.call.invite') {
          final normalizedCallId = callId.isNotEmpty ? callId : _nextCallId();
          final offerSdp = (_asMap(content['offer'])['sdp'] ?? '').toString();
          if (offerSdp.isEmpty) {
            continue;
          }

          final hasActiveCall = _activeCallId != null;
          final hasPendingIncoming = _incomingCallId != null;
          final isCurrentIncoming =
              _incomingCallId == normalizedCallId &&
              _incomingCallRoomId == roomId;
          if ((hasActiveCall || hasPendingIncoming) && !isCurrentIncoming) {
            if (_incomingCallQueue.length >= _maxQueuedIncomingCalls) {
              unawaited(
                sendCallRejectSignal(
                  roomId: roomId,
                  callId: normalizedCallId,
                  reason: 'busy',
                ),
              );
              continue;
            }

            _incomingCallQueue.add(
              _QueuedIncomingCall(
                roomId: roomId,
                callId: normalizedCallId,
                offerSdp: offerSdp,
                isVideo: isVideo,
                senderId: senderId,
                senderDisplayName: remoteDisplayName,
              ),
            );
            continue;
          }

          _activeCallId = normalizedCallId;
          _activeCallRoomId = roomId;
          _activeCallIsVideo = isVideo;
          _activeCallIsIncoming = true;
          _incomingCallId = normalizedCallId;
          _incomingCallRoomId = roomId;
          _incomingOfferSdp = offerSdp;
          _incomingCallerUserId = senderId;
          _incomingCallerDisplayName = remoteDisplayName;
          _pendingRemoteCandidates.clear();
          _armIncomingRingTimeout(roomId: roomId, callId: normalizedCallId);
          _publishSnapshot(
            ChatCallSnapshot(
              phase: ChatCallPhase.ringing,
              isVideo: isVideo,
              isIncoming: true,
              microphoneMuted: false,
              videoMuted: false,
              speakerOn: false,
              remoteUserId: senderId,
              remoteDisplayName: remoteDisplayName,
            ),
          );
          continue;
        }

        if (eventType == 'm.call.candidates') {
          if (_isMatchingCall(callId, roomId)) {
            unawaited(_applyRemoteCandidates(content));
          }
          continue;
        }

        if (eventType == 'm.call.answer') {
          if (_isMatchingCall(callId, roomId)) {
            _activeCallId = callId.isNotEmpty ? callId : _activeCallId;
            _activeCallRoomId = roomId;
            _activeCallIsVideo = isVideo;
            _cancelOutgoingRingTimeout();
            _armConnectingTimeout();
            unawaited(_applyRemoteAnswer(content));
            _publishSnapshot(
              ChatCallSnapshot(
                phase: ChatCallPhase.connected,
                isVideo: isVideo,
                isIncoming: false,
                microphoneMuted: false,
                videoMuted: false,
                speakerOn: false,
                remoteUserId: senderId,
                remoteDisplayName: remoteDisplayName,
              ),
            );
          }
          continue;
        }

        if (eventType == 'm.call.hangup' || eventType == 'm.call.reject') {
          if (_isMatchingCall(callId, roomId)) {
            unawaited(
              _endCallSession(
                clearSnapshot: false,
                promoteQueuedIncoming: true,
              ),
            );
            _publishSnapshot(
              ChatCallSnapshot(
                phase: ChatCallPhase.ended,
                isVideo: _activeCallIsVideo,
                isIncoming: false,
                microphoneMuted: false,
                videoMuted: false,
                speakerOn: false,
                remoteUserId: senderId,
                remoteDisplayName: remoteDisplayName,
              ),
            );
          }
        }
      }
    }
  }

  bool _isMatchingCall(String callId, String roomId) {
    if (_incomingCallId != null && _incomingCallRoomId != null) {
      return callId == _incomingCallId && roomId == _incomingCallRoomId;
    }
    if (_activeCallId == null || _activeCallRoomId == null) {
      return true;
    }
    return callId == _activeCallId && roomId == _activeCallRoomId;
  }

  Future<void> _applyRemoteAnswer(Map<String, dynamic> content) async {
    final answer = _asMap(content['answer']);
    final answerSdp = (answer['sdp'] ?? '').toString();
    if (answerSdp.isEmpty) {
      return;
    }
    final peer = _peerConnection;
    if (peer == null) {
      return;
    }
    final currentRemote = await peer.getRemoteDescription();
    if ((currentRemote?.sdp ?? '').isNotEmpty) {
      return;
    }
    await peer.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
    await _drainPendingRemoteCandidates();
  }

  Future<void> _applyRemoteCandidates(Map<String, dynamic> content) async {
    final candidates = _asList(content['candidates']);
    for (final raw in candidates) {
      final map = _asMap(raw);
      final candidateValue = (map['candidate'] ?? '').toString();
      if (candidateValue.isEmpty) {
        continue;
      }
      final sdpMid = map['sdpMid']?.toString();
      final lineIndexRaw = map['sdpMLineIndex'];
      final mLineIndex = lineIndexRaw is int
          ? lineIndexRaw
          : int.tryParse('$lineIndexRaw');
      final candidate = RTCIceCandidate(candidateValue, sdpMid, mLineIndex);
      final peer = _peerConnection;
      if (peer == null) {
        _pendingRemoteCandidates.add(candidate);
        continue;
      }
      await peer.addCandidate(candidate);
    }
  }

  void _captureTyping(Map<String, dynamic> sync) {
    final rooms = _asMap(sync['rooms']);
    final join = _asMap(rooms['join']);

    for (final entry in join.entries) {
      final roomId = entry.key.toString();
      final roomData = _asMap(entry.value);
      final ephemeral = _asMap(roomData['ephemeral']);
      final ephemeralEvents = _asList(ephemeral['events']);

      for (final raw in ephemeralEvents) {
        final event = _asMap(raw);
        final eventType = (event['type'] ?? '').toString();
        if (eventType == 'm.typing') {
          final content = _asMap(event['content']);
          final userIds = _asList(
            content['user_ids'],
          ).map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
          _typingUsersByRoom[roomId] = userIds;
          continue;
        }
        if (eventType == 'm.receipt') {
          _captureReadReceipts(roomId, _asMap(event['content']));
        }
      }
    }
  }

  void _captureReadReceipts(String roomId, Map<String, dynamic> content) {
    final roomReceipts = _readReceiptsByRoomEvent.putIfAbsent(
      roomId,
      () => <String, Set<String>>{},
    );

    for (final entry in content.entries) {
      final eventId = entry.key.toString();
      if (eventId.isEmpty) {
        continue;
      }
      final receiptMap = _asMap(entry.value);
      final read = _asMap(receiptMap['m.read']);
      final readPrivate = _asMap(receiptMap['m.read.private']);

      final users = <String>{};
      users.addAll(
        read.keys.map((e) => e.toString()).where((e) => e.isNotEmpty),
      );
      users.addAll(
        readPrivate.keys.map((e) => e.toString()).where((e) => e.isNotEmpty),
      );

      if (users.isNotEmpty) {
        final existing = roomReceipts[eventId] ?? <String>{};
        roomReceipts[eventId] = <String>{...existing, ...users};
      }
    }
  }

  void _emitSyncUpdate() {
    if (!_syncUpdates.isClosed) {
      _syncUpdates.add(null);
    }
  }

  void _publishSnapshot(ChatCallSnapshot snapshot) {
    _callSnapshot = snapshot;
    if (!_callUpdates.isClosed) {
      _callUpdates.add(snapshot);
    }
    unawaited(_persistCache());
  }

  void _applyThreadSyncDelta({
    required Map<dynamic, dynamic> joined,
    required Map<dynamic, dynamic> invited,
  }) {
    if (_cachedThreads.isEmpty) {
      return;
    }

    final byId = <String, ChatThread>{
      for (final thread in _cachedThreads) thread.id: thread,
    };

    for (final entry in joined.entries) {
      final roomId = entry.key.toString();
      final existing = byId[roomId];
      final roomData = _asMap(entry.value);
      final stateEvents = _asList(roomData['state']);
      if (stateEvents.isNotEmpty) {
        _cacheParticipantsFromStateEvents(roomId, stateEvents);
      }
      final timelineEnvelope = _asMap(roomData['timeline']);
      final timelineEvents = _asList(timelineEnvelope['events']);

      // Capture unread count whenever Synapse explicitly sends it in this
      // sync response. Store separately so it survives stale cache reads.
      final syncedCount = _notificationCountOrNull(roomData);
      if (syncedCount != null) {
        _syncedUnreadByRoom[roomId] = syncedCount;
      }

      // existing may be null if the room was an invite that just got accepted
      // (invite entries are separate) or is brand new. Build a minimal
      // placeholder so it gets added to the cache.
      final effectiveExisting =
          existing ??
          ChatThread(
            id: roomId,
            title: roomId,
            updatedAt: DateTime.now(),
            unreadCount: 0,
            type: ChatType.group,
            isInvited: false,
          );
      byId[roomId] = _mergeThreadDisplayFallbacks(
        _threadFromSyncDelta(
          roomId: roomId,
          roomData: roomData,
          stateEvents: stateEvents,
          timelineEvents: timelineEvents,
          existing: effectiveExisting,
          isInvited: false,
        ),
        existing: existing,
      );
    }

    for (final entry in invited.entries) {
      final roomId = entry.key.toString();
      final roomData = _asMap(entry.value);
      final stateEvents = _eventsFromEnvelope(
        _asList(roomData['invite_state']),
      );
      if (stateEvents.isNotEmpty) {
        _cacheParticipantsFromStateEvents(roomId, stateEvents);
      }
      final existing =
          byId[roomId] ??
          ChatThread(
            id: roomId,
            title: roomId,
            updatedAt: DateTime.now(),
            unreadCount: 0,
            type: ChatType.dm,
            isInvited: true,
          );
      byId[roomId] = _mergeThreadDisplayFallbacks(
        _threadFromSyncDelta(
          roomId: roomId,
          roomData: roomData,
          stateEvents: stateEvents,
          timelineEvents: const <dynamic>[],
          existing: existing,
          isInvited: true,
        ),
        existing: byId[roomId],
      );
    }

    _cachedThreads = byId.values.toList(growable: false)
      ..sort((a, b) {
        if (a.isInvited != b.isInvited) {
          return a.isInvited ? -1 : 1;
        }
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  ChatThread _threadFromSyncDelta({
    required String roomId,
    required Map<String, dynamic> roomData,
    required List<dynamic> stateEvents,
    required List<dynamic> timelineEvents,
    required ChatThread existing,
    required bool isInvited,
  }) {
    var title = stateEvents.isEmpty
        ? existing.title
        : _roomTitle(roomId, stateEvents);
    var avatarUrl = stateEvents.isEmpty
        ? existing.avatarUrl
        : _roomAvatarUrl(stateEvents);
    final isDm = stateEvents.isEmpty
        ? existing.type == ChatType.dm
        : _isLikelyDm(stateEvents);
    if (isDm) {
      final counterpart = _directMessageCounterpartForRoom(roomId, stateEvents);
      if (counterpart != null) {
        title = counterpart.displayName;
        avatarUrl = counterpart.avatarUrl ?? avatarUrl;
      }
    }

    final unread = isInvited
        ? 0
        : (_notificationCountOrNull(roomData) ?? existing.unreadCount);
    final lastEvent = _latestMessageEvent(timelineEvents);
    final updatedAt = lastEvent != null
        ? _roomEventDate(lastEvent, stateEvents)
        : existing.updatedAt;
    final incSenderEntry = _lastMessageSenderByRoom[roomId] ?? '';
    final incCachedIsMe = incSenderEntry == 'me';
    final senderName = lastEvent != null
        ? _eventSenderLabel(lastEvent, stateEvents)
        : (incCachedIsMe ? '' : incSenderEntry);
    final previewBody = lastEvent != null
        ? _displayBodyFromEvent(lastEvent)
        : (_lastMessagePreviewByRoom[roomId] ?? '');
    final lastEventSenderId = lastEvent != null
        ? (lastEvent['sender'] ?? '').toString()
        : '';
    final incIsMe = lastEvent != null
        ? (lastEventSenderId.isNotEmpty &&
              lastEventSenderId == (currentUserId ?? ''))
        : incCachedIsMe;
    if (lastEvent != null) {
      _lastMessageTimeByRoom[roomId] = updatedAt;
      _lastMessageSenderByRoom[roomId] = incIsMe ? 'me' : senderName;
      _lastMessageSenderIdByRoom[roomId] = lastEventSenderId;
      _lastMessagePreviewByRoom[roomId] = previewBody;
    }
    final lastMessage = previewBody.trim().isNotEmpty
        ? _formatThreadPreview(
            senderName: senderName,
            body: previewBody,
            isMe: incIsMe,
          )
        : existing.lastMessage;

    return existing.copyWith(
      title: title,
      updatedAt: updatedAt,
      lastMessage: lastMessage,
      unreadCount: unread,
      avatarUrl: avatarUrl,
      type: isDm ? ChatType.dm : ChatType.group,
      isInvited: isInvited,
    );
  }

  Map<String, Map<String, Set<String>>> _compactReadReceiptsForCache(
    Map<String, Map<String, Set<String>>> source,
  ) {
    final out = <String, Map<String, Set<String>>>{};
    for (final roomEntry in source.entries) {
      final roomId = roomEntry.key;
      final eventEntries = roomEntry.value.entries.toList(growable: false)
        ..sort((a, b) => a.key.compareTo(b.key));
      final start = eventEntries.length > _maxCachedReceiptEventsPerRoom
          ? eventEntries.length - _maxCachedReceiptEventsPerRoom
          : 0;
      final trimmed = <String, Set<String>>{};
      for (final entry in eventEntries.skip(start)) {
        trimmed[entry.key] = <String>{...entry.value};
      }
      if (trimmed.isNotEmpty) {
        out[roomId] = trimmed;
      }
    }
    return out;
  }

  Map<String, dynamic> _chatCallSnapshotToMap(ChatCallSnapshot snapshot) {
    return <String, dynamic>{
      'phase': snapshot.phase.name,
      'isVideo': snapshot.isVideo,
      'isIncoming': snapshot.isIncoming,
      'microphoneMuted': snapshot.microphoneMuted,
      'videoMuted': snapshot.videoMuted,
      'speakerOn': snapshot.speakerOn,
      'remoteUserId': snapshot.remoteUserId,
      'remoteDisplayName': snapshot.remoteDisplayName,
      'remoteAvatarUrl': snapshot.remoteAvatarUrl,
      'error': snapshot.error,
    };
  }

  ChatCallSnapshot? _chatCallSnapshotFromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) {
      return null;
    }
    final phaseRaw = (map['phase'] ?? '').toString();
    final phase = ChatCallPhase.values.firstWhere(
      (value) => value.name == phaseRaw,
      orElse: () => ChatCallPhase.idle,
    );
    return ChatCallSnapshot(
      phase: phase,
      isVideo: map['isVideo'] == true,
      isIncoming: map['isIncoming'] == true,
      microphoneMuted: map['microphoneMuted'] == true,
      videoMuted: map['videoMuted'] == true,
      speakerOn: map['speakerOn'] == true,
      remoteUserId: map['remoteUserId']?.toString(),
      remoteDisplayName: map['remoteDisplayName']?.toString(),
      remoteAvatarUrl: map['remoteAvatarUrl']?.toString(),
      error: map['error']?.toString(),
    );
  }

  Future<Map<String, dynamic>?> _safeGetEvent({
    required String roomId,
    required String eventId,
  }) async {
    try {
      return await _core.getEvent(roomId, eventId);
    } catch (_) {
      return null;
    }
  }

  List<dynamic> _asList(Object? value) {
    if (value is List<dynamic>) return value;
    if (value is Map<String, dynamic> && value['events'] is List<dynamic>) {
      return value['events'] as List<dynamic>;
    }
    return const <dynamic>[];
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  bool _isVideoCallContent(Map<String, dynamic> content) {
    if (content['is_video'] == true) {
      return true;
    }
    final offer = _asMap(content['offer']);
    final sdp = (offer['sdp'] ?? '').toString().toLowerCase();
    return sdp.contains('m=video');
  }

  String? _displayNameForRoomUser(String roomId, String userId) {
    final participants =
        _participantsCache[roomId] ?? const <ChatParticipant>[];
    for (final participant in participants) {
      if (participant.userId == userId) {
        final cleaned = _sanitizeSenderLabel(participant.displayName);
        if (cleaned.isNotEmpty) {
          return cleaned;
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _eventsFromEnvelope(List<dynamic> envelope) {
    return envelope
        .map(_asMap)
        .map(
          (event) =>
              event.containsKey('content') ? event : _asMap(event['event']),
        )
        .toList(growable: false);
  }

  ChatThread? _cachedThreadById(String roomId) {
    for (final thread in _cachedThreads) {
      if (thread.id == roomId) {
        return thread;
      }
    }
    return null;
  }

  ChatThread _mergeThreadDisplayFallbacks(
    ChatThread candidate, {
    ChatThread? existing,
  }) {
    if (existing == null) {
      return candidate;
    }

    final hasUsefulTitle = _hasUsefulThreadTitle(candidate.title, candidate.id);
    final fallbackTitle = _hasUsefulThreadTitle(existing.title, existing.id)
        ? existing.title
        : candidate.title;
    final fallbackMessage = (candidate.lastMessage ?? '').trim().isNotEmpty
        ? candidate.lastMessage
        : existing.lastMessage;
    return candidate.copyWith(
      title: hasUsefulTitle ? candidate.title : fallbackTitle,
      lastMessage: fallbackMessage,
      avatarUrl: candidate.avatarUrl ?? existing.avatarUrl,
    );
  }

  bool _hasUsefulThreadTitle(String title, String roomId) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == roomId) {
      return false;
    }
    if ((trimmed.startsWith('!') || trimmed.startsWith('@')) &&
        trimmed.contains(':')) {
      return false;
    }
    return true;
  }

  bool _shouldHideIncompleteThread(ChatThread thread, {ChatThread? existing}) {
    if (existing != null) {
      return false;
    }
    final hasUsefulTitle = _hasUsefulThreadTitle(thread.title, thread.id);
    final hasPreview = (thread.lastMessage ?? '').trim().isNotEmpty;
    return !thread.isInvited &&
        !hasUsefulTitle &&
        !hasPreview &&
        thread.avatarUrl == null;
  }

  Future<void> _reportThreadBuildProgress({
    required int processedRooms,
    required int totalRooms,
    required void Function(double progress, String status)? onProgress,
  }) async {
    if (totalRooms <= 0) {
      return;
    }
    final ratio = processedRooms / totalRooms;
    onProgress?.call(
      (0.72 + (ratio * 0.26)).clamp(0.72, 0.98).toDouble(),
      'Loading conversations... $processedRooms/$totalRooms',
    );
    if (processedRooms < totalRooms && processedRooms % 4 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  String _roomTitle(String roomId, List<dynamic> stateEvents) {
    final events = stateEvents.map(_asMap).toList(growable: false);
    for (final event in events) {
      if ((event['type'] ?? '').toString() != 'm.room.name') continue;
      final content = _asMap(event['content']);
      final name = (content['name'] ?? '').toString().trim();
      if (name.isNotEmpty && !_isGenericDirectMessageName(name)) {
        return name;
      }
    }

    final otherMember = events.firstWhere(
      (event) =>
          (event['type'] ?? '').toString() == 'm.room.member' &&
          (event['state_key'] ?? '').toString() != (currentUserId ?? '') &&
          (_asMap(event['content'])['membership'] ?? '').toString() == 'join',
      orElse: () => const <String, dynamic>{},
    );
    if (otherMember.isNotEmpty) {
      final content = _asMap(otherMember['content']);
      final display = (content['displayname'] ?? '').toString().trim();
      final stateKey = (otherMember['state_key'] ?? '').toString();
      if (display.isNotEmpty) return display;
      if (stateKey.isNotEmpty) return stateKey;
    }

    return roomId;
  }

  void _cacheParticipantsFromStateEvents(
    String roomId,
    List<dynamic> stateEvents,
  ) {
    final participants = _participantsFromStateEvents(stateEvents);
    if (participants.isEmpty) {
      return;
    }
    _participantsCache[roomId] = participants;
    _participantsCacheAt[roomId] = DateTime.now();
  }

  List<ChatParticipant> _participantsFromStateEvents(
    List<dynamic> stateEvents,
  ) {
    final out = <ChatParticipant>[];
    for (final event in stateEvents.map(_asMap)) {
      if ((event['type'] ?? '').toString() != 'm.room.member') continue;
      final stateKey = (event['state_key'] ?? '').toString().trim();
      if (stateKey.isEmpty) continue;

      final content = _asMap(event['content']);
      final membership = (content['membership'] ?? '').toString();
      if (membership != 'join' && membership != 'invite') continue;

      final displayNameRaw = (content['displayname'] ?? '').toString().trim();
      out.add(
        ChatParticipant(
          userId: stateKey,
          displayName: displayNameRaw.isEmpty ? stateKey : displayNameRaw,
          level: ChatMemberLevel.member,
          membership: membership,
          avatarUrl: _mxcToThumbnailHttp(content['avatar_url']),
        ),
      );
    }
    out.sort((a, b) => a.displayName.compareTo(b.displayName));
    return out;
  }

  bool _hasExplicitRoomName(List<dynamic> stateEvents) {
    for (final event in stateEvents.map(_asMap)) {
      if ((event['type'] ?? '').toString() != 'm.room.name') continue;
      final name = (_asMap(event['content'])['name'] ?? '').toString().trim();
      if (name.isNotEmpty && !_isGenericDirectMessageName(name)) {
        return true;
      }
    }
    return false;
  }

  bool _isGenericDirectMessageName(String name) {
    final normalized = name.trim().toLowerCase();
    return normalized == 'direct message' ||
        normalized == 'direct messages' ||
        normalized == 'dm';
  }

  ChatParticipant? _directMessageCounterpart(List<dynamic> stateEvents) {
    final events = stateEvents.map(_asMap).toList(growable: false);
    final otherMember = events.firstWhere(
      (event) =>
          (event['type'] ?? '').toString() == 'm.room.member' &&
          (event['state_key'] ?? '').toString() != (currentUserId ?? '') &&
          (_asMap(event['content'])['membership'] ?? '').toString() != 'leave',
      orElse: () => const <String, dynamic>{},
    );
    if (otherMember.isEmpty) {
      return null;
    }

    final content = _asMap(otherMember['content']);
    final stateKey = (otherMember['state_key'] ?? '').toString();
    final displayName = (content['displayname'] ?? '').toString().trim();
    return ChatParticipant(
      userId: stateKey,
      displayName: displayName.isEmpty ? stateKey : displayName,
      level: ChatMemberLevel.member,
      membership: (content['membership'] ?? '').toString(),
      avatarUrl: _mxcToThumbnailHttp(content['avatar_url']),
    );
  }

  ChatParticipant? _directMessageCounterpartForRoom(
    String roomId,
    List<dynamic> stateEvents,
  ) {
    final fromState = _directMessageCounterpart(stateEvents);
    if (fromState != null &&
        _isUsefulDirectMessageCounterpart(fromState, roomId)) {
      return fromState;
    }

    final cachedParticipants =
        _participantsCache[roomId] ?? const <ChatParticipant>[];
    for (final participant in cachedParticipants) {
      if (participant.userId == (currentUserId ?? '')) {
        continue;
      }
      if (participant.membership == 'leave') {
        continue;
      }
      if (_isUsefulDirectMessageCounterpart(participant, roomId)) {
        return participant;
      }
    }

    return fromState;
  }

  bool _isUsefulDirectMessageCounterpart(
    ChatParticipant participant,
    String roomId,
  ) {
    return _hasUsefulThreadTitle(participant.displayName, roomId) ||
        (participant.avatarUrl ?? '').trim().isNotEmpty;
  }

  String? _roomAvatarUrl(List<dynamic> stateEvents) {
    final events = stateEvents.map(_asMap).toList(growable: false);

    for (final event in events) {
      if ((event['type'] ?? '').toString() != 'm.room.avatar') continue;
      final content = _asMap(event['content']);
      final url = _mxcToThumbnailHttp(content['url']);
      if ((url ?? '').isNotEmpty) return url;
    }

    final otherMember = events.firstWhere(
      (event) =>
          (event['type'] ?? '').toString() == 'm.room.member' &&
          (event['state_key'] ?? '').toString() != (currentUserId ?? '') &&
          (_asMap(event['content'])['membership'] ?? '').toString() == 'join',
      orElse: () => const <String, dynamic>{},
    );
    if (otherMember.isNotEmpty) {
      return _mxcToThumbnailHttp(_asMap(otherMember['content'])['avatar_url']);
    }

    return null;
  }

  ChatEncryptionStatus _roomEncryptionStatus(List<dynamic> stateEvents) {
    for (final raw in stateEvents) {
      final event = _asMap(raw);
      if ((event['type'] ?? '').toString() != 'm.room.encryption') {
        continue;
      }
      final content = _asMap(event['content']);
      final algorithm = (content['algorithm'] ?? '').toString().trim();
      return ChatEncryptionStatus(
        isEncrypted: true,
        algorithm: algorithm.isEmpty ? null : algorithm,
      );
    }
    return const ChatEncryptionStatus.unencrypted();
  }

  void _updateCachedThreadAvatar(String roomId, String? avatarUrl) {
    final threadIndex = _cachedThreads.indexWhere(
      (thread) => thread.id == roomId,
    );
    if (threadIndex < 0) {
      return;
    }
    final mutable = List<ChatThread>.from(_cachedThreads);
    mutable[threadIndex] = mutable[threadIndex].copyWith(avatarUrl: avatarUrl);
    _cachedThreads = mutable;
    unawaited(_persistCache());
  }

  int _notificationCount(Map<String, dynamic> roomData) {
    return _notificationCountOrNull(roomData) ?? 0;
  }

  int? _notificationCountOrNull(Map<String, dynamic> roomData) {
    if (roomData.containsKey('unread_notifications')) {
      final unread = _asMap(roomData['unread_notifications']);
      final count = _coerceInt(unread['notification_count']);
      if (count != null) return count;
      final highlightCount = _coerceInt(unread['highlight_count']);
      if (highlightCount != null) return highlightCount;
      return 0;
    }
    if (roomData.containsKey('notification_count')) {
      return _coerceInt(roomData['notification_count']) ?? 0;
    }
    final unread = _asMap(roomData['unread_notifications']);
    final count = _coerceInt(unread['notification_count']);
    if (count != null) return count;
    final highlightCount = _coerceInt(unread['highlight_count']);
    if (highlightCount != null) return highlightCount;
    final unreadCount = _coerceInt(roomData['notification_count']);
    if (unreadCount != null) return unreadCount;
    return null;
  }

  int? _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _isLikelyDm(List<dynamic> stateEvents) {
    if (_hasExplicitRoomName(stateEvents)) {
      return false;
    }
    final members = stateEvents
        .map(_asMap)
        .where(
          (event) =>
              (event['type'] ?? '').toString() == 'm.room.member' &&
              (_asMap(event['content'])['membership'] ?? '').toString() ==
                  'join',
        )
        .length;
    return members <= 2;
  }

  Map<String, dynamic>? _latestMessageEvent(List<dynamic> timelineEvents) {
    final messages = timelineEvents
        .map(_asMap)
        .where((event) {
          if ((event['type'] ?? '').toString() != 'm.room.message') {
            return false;
          }
          final unsigned = _asMap(event['unsigned']);
          if (unsigned.containsKey('redacted_because') ||
              unsigned.containsKey('redacted_by')) {
            return false;
          }
          final content = _asMap(event['content']);
          final msgType = (content['msgtype'] ?? '').toString().trim();
          final body = (content['body'] ?? '').toString().trim();
          final relatesTo = _asMap(content['m.relates_to']);
          return msgType.isNotEmpty || body.isNotEmpty || relatesTo.isNotEmpty;
        })
        .toList(growable: false);
    if (messages.isEmpty) return null;
    messages.sort((a, b) => _eventTimestamp(a).compareTo(_eventTimestamp(b)));
    return messages.last;
  }

  Future<Map<String, dynamic>?> _loadLatestMessageEvent(String roomId) async {
    try {
      final raw = await _core.getRoomMessagesRaw(roomId, limit: 20);
      final chunk = _asList(raw['chunk']);
      return _latestMessageEvent(chunk);
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> _loadRoomStateEvents(String roomId) async {
    try {
      return await _core.getStateEvents(roomId);
    } catch (_) {
      return const <dynamic>[];
    }
  }

  DateTime _roomEventDate(
    Map<String, dynamic>? lastEvent,
    List<dynamic> stateEvents,
  ) {
    // Prefer last message timestamp
    if (lastEvent != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        _eventTimestamp(lastEvent),
        isUtc: true,
      );
    }
    // Fall back to room creation time
    final creationDate = _getRoomCreationDate(stateEvents);
    if (creationDate != null) return creationDate;
    // Last resort: current time (shouldn't happen)
    return DateTime.now();
  }

  DateTime? _getRoomCreationDate(List<dynamic> stateEvents) {
    final events = stateEvents.map(_asMap).toList(growable: false);
    for (final event in events) {
      if ((event['type'] ?? '').toString() != 'm.room.create') continue;
      final ts = event['origin_server_ts'];
      if (ts is int) {
        return DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
      }
    }
    return null;
  }

  int _eventTimestamp(Map<String, dynamic> event) {
    final ts = event['origin_server_ts'];
    if (ts is int) return ts;
    return DateTime.now().millisecondsSinceEpoch;
  }

  String? _extractReplyEventId(Map<String, dynamic> content) {
    final relatesTo = _asMap(content['m.relates_to']);
    final inReplyTo = _asMap(relatesTo['m.in_reply_to']);
    final eventId = (inReplyTo['event_id'] ?? '').toString();
    return eventId.isEmpty ? null : eventId;
  }

  MessageKind _mapMessageKind(Map<String, dynamic> content) {
    final msgType = (content['msgtype'] ?? '').toString();
    if (msgType == 'm.image') return MessageKind.image;
    if (msgType == 'm.video') return MessageKind.video;

    final body = (content['body'] ?? '').toString().trim();
    if (body.isNotEmpty && body.runes.length <= 3) {
      return MessageKind.emoji;
    }
    return MessageKind.text;
  }

  String _resolveSenderName(
    String senderId,
    Map<String, String> displayNamesByUserId,
  ) {
    final displayName = _sanitizeSenderLabel(
      displayNamesByUserId[senderId]?.trim() ?? '',
    );
    if (displayName.isNotEmpty) {
      return displayName;
    }
    return 'Unknown';
  }

  String _eventSenderLabel(
    Map<String, dynamic> event,
    List<dynamic> stateEvents,
  ) {
    final senderId = (event['sender'] ?? '').toString();
    if (senderId.isEmpty) {
      return '';
    }

    final byUserId = <String, String>{};
    for (final raw in stateEvents) {
      final state = _asMap(raw);
      if ((state['type'] ?? '').toString() != 'm.room.member') {
        continue;
      }
      final userId = (state['state_key'] ?? '').toString();
      if (userId.isEmpty) {
        continue;
      }
      final display = (_asMap(state['content'])['displayname'] ?? '')
          .toString()
          .trim();
      byUserId[userId] = display;
    }

    final resolved = _resolveSenderName(senderId, byUserId);
    final cleaned = _sanitizeSenderLabel(resolved);
    if (cleaned.isNotEmpty && cleaned != 'Unknown') {
      return cleaned;
    }
    return '';
  }

  String _formatThreadPreview({
    required String senderName,
    required String body,
    bool isMe = false,
  }) {
    final sender = isMe ? 'You' : senderName.trim();
    final preview = body.trim();
    if (sender.isEmpty || preview.isEmpty) {
      return preview;
    }
    if (preview.startsWith('$sender:')) {
      return preview;
    }
    return '$sender: $preview';
  }

  String _sanitizeSenderLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final withoutObjectType = trimmed
        .replaceFirst(RegExp(r'\s*<[^>]+>\s*$'), '')
        .trim();
    if (withoutObjectType.isEmpty) {
      return '';
    }

    if (withoutObjectType.startsWith('@') && withoutObjectType.contains(':')) {
      return '';
    }

    return withoutObjectType;
  }

  String _displayBodyFromEvent(Map<String, dynamic>? event) {
    if (event == null) return '';
    final content = _asMap(event['content']);
    final msgType = (content['msgtype'] ?? '').toString();
    final body = _stripReplyFallback((content['body'] ?? '').toString());
    final caption = (content['org.cluborbit.caption'] ?? '').toString().trim();
    final mime = (_asMap(content['info'])['mimetype'] ?? '').toString().trim();
    final filename = (content['filename'] ?? content['body'] ?? '')
        .toString()
        .trim();

    if (msgType == 'm.image') {
      return caption.isNotEmpty ? '🖼 $caption' : '[Image]';
    }
    if (msgType == 'm.video') {
      return caption.isNotEmpty ? '🎬 $caption' : '[Video]';
    }
    if (msgType == 'm.file') {
      if (_isAudioFile(mimeType: mime, filename: filename)) {
        return '🎤 Voice message';
      }
      return '📎 [File]';
    }
    return _stripForwardPrefix(body);
  }

  bool _isAudioFile({required String mimeType, required String filename}) {
    final mime = mimeType.toLowerCase();
    if (mime.startsWith('audio/')) {
      return true;
    }
    final name = filename.toLowerCase();
    return name.endsWith('.m4a') ||
        name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.aac') ||
        name.endsWith('.ogg');
  }

  String _bodyFromContent(Map<String, dynamic> content) {
    final body = _stripReplyFallback((content['body'] ?? '').toString());
    if (body.isNotEmpty) return body;
    final filename = (content['filename'] ?? '').toString();
    if (filename.isNotEmpty) return filename;
    return '';
  }

  String _callInviteTimelineBody({
    required String senderName,
    required Map<String, dynamic> content,
  }) {
    final label = _sanitizeSenderLabel(senderName);
    final name = label.isEmpty ? 'Someone' : label;
    final noun = _isVideoCallContent(content) ? 'a video call' : 'a call';
    return '$name started $noun';
  }

  bool _isJoinMembershipEvent(Map<String, dynamic> event) {
    if ((event['type'] ?? '').toString() != 'm.room.member') {
      return false;
    }
    final content = _asMap(event['content']);
    if ((content['membership'] ?? '').toString() != 'join') {
      return false;
    }
    final previousContent = _asMap(
      _asMap(event['unsigned'])['prev_content'] ?? event['prev_content'],
    );
    return (previousContent['membership'] ?? '').toString() != 'join';
  }

  bool _isProfileDisplayNameChangeEvent(Map<String, dynamic> event) {
    if ((event['type'] ?? '').toString() != 'm.room.member') {
      return false;
    }
    final content = _asMap(event['content']);
    if ((content['membership'] ?? '').toString() != 'join') {
      return false;
    }
    final previousContent = _previousMembershipContent(event);
    if ((previousContent['membership'] ?? '').toString() != 'join') {
      return false;
    }
    final currentName = _sanitizeSenderLabel(
      (content['displayname'] ?? '').toString(),
    );
    final previousName = _sanitizeSenderLabel(
      (previousContent['displayname'] ?? '').toString(),
    );
    return currentName != previousName;
  }

  bool _isProfileAvatarChangeEvent(Map<String, dynamic> event) {
    if ((event['type'] ?? '').toString() != 'm.room.member') {
      return false;
    }
    final content = _asMap(event['content']);
    if ((content['membership'] ?? '').toString() != 'join') {
      return false;
    }
    final previousContent = _previousMembershipContent(event);
    if ((previousContent['membership'] ?? '').toString() != 'join') {
      return false;
    }
    final currentAvatar = (content['avatar_url'] ?? '').toString().trim();
    final previousAvatar = (previousContent['avatar_url'] ?? '')
        .toString()
        .trim();
    return currentAvatar != previousAvatar;
  }

  Map<String, dynamic> _previousMembershipContent(Map<String, dynamic> event) {
    return _asMap(
      _asMap(event['unsigned'])['prev_content'] ?? event['prev_content'],
    );
  }

  String _joinTimelineBody({
    required Map<String, dynamic> event,
    required String senderName,
    required Map<String, String> displayNamesByUserId,
  }) {
    final content = _asMap(event['content']);
    final stateKey = (event['state_key'] ?? '').toString().trim();
    final contentDisplayName = _sanitizeSenderLabel(
      (content['displayname'] ?? '').toString(),
    );
    final cachedDisplayName = _sanitizeSenderLabel(
      displayNamesByUserId[stateKey] ?? '',
    );
    final senderDisplayName = _sanitizeSenderLabel(senderName);
    final name = contentDisplayName.isNotEmpty
        ? contentDisplayName
        : cachedDisplayName.isNotEmpty
        ? cachedDisplayName
        : senderDisplayName.isNotEmpty
        ? senderDisplayName
        : 'Someone';
    return '$name joined';
  }

  String _profileUpdateTimelineBody({
    required Map<String, dynamic> event,
    required String senderName,
    required Map<String, String> displayNamesByUserId,
    required bool changedAvatar,
    required bool changedDisplayName,
  }) {
    final content = _asMap(event['content']);
    final stateKey = (event['state_key'] ?? '').toString().trim();
    final contentDisplayName = _sanitizeSenderLabel(
      (content['displayname'] ?? '').toString(),
    );
    final cachedDisplayName = _sanitizeSenderLabel(
      displayNamesByUserId[stateKey] ?? '',
    );
    final senderDisplayName = _sanitizeSenderLabel(senderName);
    final name = contentDisplayName.isNotEmpty
        ? contentDisplayName
        : cachedDisplayName.isNotEmpty
        ? cachedDisplayName
        : senderDisplayName.isNotEmpty
        ? senderDisplayName
        : 'Someone';
    if (changedAvatar && changedDisplayName) {
      return '$name updated profile photo and display name';
    }
    if (changedAvatar) {
      return '$name changed profile photo';
    }
    return '$name changed display name';
  }

  String _replyPreviewBodyFromContent(Map<String, dynamic> content) {
    final msgType = (content['msgtype'] ?? '').toString();
    final caption = (content['org.cluborbit.caption'] ?? '').toString().trim();
    if ((msgType == 'm.image' || msgType == 'm.video') && caption.isNotEmpty) {
      return caption;
    }
    if (msgType == 'm.image' || msgType == 'm.video') {
      return '';
    }
    return _bodyFromContent(content);
  }

  String _stripReplyFallback(String body) {
    final normalized = body.replaceAll('\r\n', '\n');
    if (normalized.trim().isEmpty) {
      return '';
    }

    final lines = normalized.split('\n');
    var index = 0;
    while (index < lines.length && lines[index].trimLeft().startsWith('>')) {
      index++;
    }

    if (index == 0) {
      return normalized.trim();
    }

    while (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }

    final remainder = lines.skip(index).join('\n').trim();
    return remainder.isEmpty ? normalized.trim() : remainder;
  }

  String? _mxcToThumbnailHttp(Object? value) {
    final raw = (value ?? '').toString();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'mxc') return null;
    final result = _core.mxcToThumbnailHttp(uri);
    return result.isEmpty ? null : result;
  }

  String? _mxcToDownloadHttp(Object? value) {
    final raw = (value ?? '').toString();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'mxc') return null;
    final result = _core.mxcToDownloadHttp(uri);
    return result.isEmpty ? null : result;
  }

  String? _mediaUrl(Map<String, dynamic> content) {
    final direct = _mxcToDownloadHttp(content['url']);
    if ((direct ?? '').isNotEmpty) return direct;
    final encrypted = _asMap(content['file']);
    final encryptedUrl = _mxcToDownloadHttp(encrypted['url']);
    if ((encryptedUrl ?? '').isNotEmpty) return encryptedUrl;
    return null;
  }

  String? _thumbnailUrl(Map<String, dynamic> content) {
    final info = _asMap(content['info']);
    final thumb = _mxcToThumbnailHttp(info['thumbnail_url']);
    if ((thumb ?? '').isNotEmpty) return thumb;
    final thumbFile = _asMap(info['thumbnail_file']);
    final encryptedThumb = _mxcToThumbnailHttp(thumbFile['url']);
    if ((encryptedThumb ?? '').isNotEmpty) return encryptedThumb;
    return _mxcToThumbnailHttp(content['url']);
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
}
