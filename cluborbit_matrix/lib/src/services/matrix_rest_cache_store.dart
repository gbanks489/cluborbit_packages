import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cluborbit_models/cluborbit_models.dart';

class MatrixRestCacheSnapshot {
  const MatrixRestCacheSnapshot({
    required this.sinceToken,
    required this.threads,
    required this.participantsByRoom,
    required this.messagesByRoom,
    required this.typingUsersByRoom,
    required this.readReceiptsByRoomEvent,
    required this.callSnapshot,
    required this.updatedAtMs,
    required this.lastMessageSenderByRoom,
    required this.lastMessagePreviewByRoom,
  });

  final String? sinceToken;
  final List<ChatThread> threads;
  final Map<String, List<ChatParticipant>> participantsByRoom;
  final Map<String, List<ChatMessage>> messagesByRoom;
  final Map<String, Set<String>> typingUsersByRoom;
  final Map<String, Map<String, Set<String>>> readReceiptsByRoomEvent;
  final Map<String, dynamic>? callSnapshot;
  final int updatedAtMs;
  final Map<String, String> lastMessageSenderByRoom;
  final Map<String, String> lastMessagePreviewByRoom;
}

class MatrixRestCacheStore {
  MatrixRestCacheStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  String _key({required String databaseName, required String userId}) {
    return 'matrix_rest_cache::$databaseName::$userId';
  }

  Future<MatrixRestCacheSnapshot?> load({
    required String databaseName,
    required String userId,
  }) async {
    final raw = await _storage.read(
      key: _key(databaseName: databaseName, userId: userId),
    );
    if ((raw ?? '').trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw!);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final sinceRaw = decoded['sinceToken'];
      final sinceToken = sinceRaw is String && sinceRaw.trim().isNotEmpty
          ? sinceRaw.trim()
          : null;

      final updatedAtRaw = decoded['updatedAtMs'];
      final updatedAtMs = updatedAtRaw is int
          ? updatedAtRaw
          : int.tryParse('$updatedAtRaw') ?? 0;

      final threadsRaw = decoded['threads'];
      final threadsList = threadsRaw is List ? threadsRaw : const <dynamic>[];
      final threads = threadsList
          .whereType<Map>()
          .map((entry) => entry.map((k, v) => MapEntry(k.toString(), v)))
          .map(_threadFromMap)
          .toList(growable: false);

      final participantsByRoomRaw = decoded['participantsByRoom'];
      final participantsByRoomMap = participantsByRoomRaw is Map
          ? participantsByRoomRaw
          : const <dynamic, dynamic>{};
      final participantsByRoom = <String, List<ChatParticipant>>{};
      for (final entry in participantsByRoomMap.entries) {
        final roomId = entry.key.toString();
        final rawList = entry.value is List
            ? entry.value as List
            : const <dynamic>[];
        final participants = rawList
            .whereType<Map>()
            .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
            .map(_participantFromMap)
            .toList(growable: false);
        if (roomId.isNotEmpty && participants.isNotEmpty) {
          participantsByRoom[roomId] = participants;
        }
      }

      final messagesByRoomRaw = decoded['messagesByRoom'];
      final messagesByRoomMap = messagesByRoomRaw is Map
          ? messagesByRoomRaw
          : const <dynamic, dynamic>{};
      final messagesByRoom = <String, List<ChatMessage>>{};
      for (final entry in messagesByRoomMap.entries) {
        final roomId = entry.key.toString();
        final rawList = entry.value is List
            ? entry.value as List
            : const <dynamic>[];
        final messages = rawList
            .whereType<Map>()
            .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
            .map(_messageFromMap)
            .toList(growable: false);
        if (roomId.isNotEmpty && messages.isNotEmpty) {
          messagesByRoom[roomId] = messages;
        }
      }

      final typingRaw = decoded['typingUsersByRoom'];
      final typingMap = typingRaw is Map
          ? typingRaw
          : const <dynamic, dynamic>{};
      final typingUsersByRoom = <String, Set<String>>{};
      for (final entry in typingMap.entries) {
        final roomId = entry.key.toString();
        final usersRaw = entry.value is List
            ? entry.value as List
            : const <dynamic>[];
        final users = usersRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet();
        if (roomId.isNotEmpty && users.isNotEmpty) {
          typingUsersByRoom[roomId] = users;
        }
      }

      final receiptsRaw = decoded['readReceiptsByRoomEvent'];
      final receiptsMap = receiptsRaw is Map
          ? receiptsRaw
          : const <dynamic, dynamic>{};
      final readReceiptsByRoomEvent = <String, Map<String, Set<String>>>{};
      for (final roomEntry in receiptsMap.entries) {
        final roomId = roomEntry.key.toString();
        final roomValue = roomEntry.value is Map
            ? roomEntry.value as Map
            : const <dynamic, dynamic>{};
        final roomReceipts = <String, Set<String>>{};
        for (final eventEntry in roomValue.entries) {
          final eventId = eventEntry.key.toString();
          final usersRaw = eventEntry.value is List
              ? eventEntry.value as List
              : const <dynamic>[];
          final users = usersRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet();
          if (eventId.isNotEmpty && users.isNotEmpty) {
            roomReceipts[eventId] = users;
          }
        }
        if (roomId.isNotEmpty && roomReceipts.isNotEmpty) {
          readReceiptsByRoomEvent[roomId] = roomReceipts;
        }
      }

      final callSnapshotRaw = decoded['callSnapshot'];
      final callSnapshot = callSnapshotRaw is Map
          ? callSnapshotRaw.map((k, v) => MapEntry(k.toString(), v))
          : null;

      final senderByRoomRaw = decoded['lastMessageSenderByRoom'];
      final lastMessageSenderByRoom = <String, String>{};
      if (senderByRoomRaw is Map) {
        for (final e in senderByRoomRaw.entries) {
          final k = e.key.toString();
          final v = e.value?.toString() ?? '';
          if (k.isNotEmpty) lastMessageSenderByRoom[k] = v;
        }
      }

      final previewByRoomRaw = decoded['lastMessagePreviewByRoom'];
      final lastMessagePreviewByRoom = <String, String>{};
      if (previewByRoomRaw is Map) {
        for (final e in previewByRoomRaw.entries) {
          final k = e.key.toString();
          final v = e.value?.toString() ?? '';
          if (k.isNotEmpty) lastMessagePreviewByRoom[k] = v;
        }
      }

      return MatrixRestCacheSnapshot(
        sinceToken: sinceToken,
        threads: threads,
        participantsByRoom: participantsByRoom,
        messagesByRoom: messagesByRoom,
        typingUsersByRoom: typingUsersByRoom,
        readReceiptsByRoomEvent: readReceiptsByRoomEvent,
        callSnapshot: callSnapshot,
        updatedAtMs: updatedAtMs,
        lastMessageSenderByRoom: lastMessageSenderByRoom,
        lastMessagePreviewByRoom: lastMessagePreviewByRoom,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String databaseName,
    required String userId,
    required String? sinceToken,
    required List<ChatThread> threads,
    required Map<String, List<ChatParticipant>> participantsByRoom,
    required Map<String, List<ChatMessage>> messagesByRoom,
    required Map<String, Set<String>> typingUsersByRoom,
    required Map<String, Map<String, Set<String>>> readReceiptsByRoomEvent,
    required Map<String, dynamic>? callSnapshot,
    required Map<String, String> lastMessageSenderByRoom,
    required Map<String, String> lastMessagePreviewByRoom,
  }) async {
    final payload = <String, dynamic>{
      'sinceToken': sinceToken,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'threads': threads.map(_threadToMap).toList(growable: false),
      'participantsByRoom': participantsByRoom.map(
        (roomId, participants) => MapEntry(
          roomId,
          participants.map(_participantToMap).toList(growable: false),
        ),
      ),
      'messagesByRoom': messagesByRoom.map(
        (roomId, messages) => MapEntry(
          roomId,
          messages.map(_messageToMap).toList(growable: false),
        ),
      ),
      'typingUsersByRoom': typingUsersByRoom.map(
        (roomId, users) => MapEntry(roomId, users.toList(growable: false)),
      ),
      'readReceiptsByRoomEvent': readReceiptsByRoomEvent.map(
        (roomId, eventToUsers) => MapEntry(
          roomId,
          eventToUsers.map(
            (eventId, users) =>
                MapEntry(eventId, users.toList(growable: false)),
          ),
        ),
      ),
      'callSnapshot': callSnapshot,
      'lastMessageSenderByRoom': lastMessageSenderByRoom,
      'lastMessagePreviewByRoom': lastMessagePreviewByRoom,
    };
    await _storage.write(
      key: _key(databaseName: databaseName, userId: userId),
      value: jsonEncode(payload),
    );
  }

  Map<String, dynamic> _threadToMap(ChatThread thread) {
    return <String, dynamic>{
      'id': thread.id,
      'title': thread.title,
      'updatedAtMs': thread.updatedAt.millisecondsSinceEpoch,
      'lastMessage': thread.lastMessage,
      'unreadCount': thread.unreadCount,
      'avatarUrl': thread.avatarUrl,
      'type': thread.type.name,
      'isInvited': thread.isInvited,
    };
  }

  ChatThread _threadFromMap(Map<String, dynamic> map) {
    final updatedAtRaw = map['updatedAtMs'];
    final updatedAtMs = updatedAtRaw is int
        ? updatedAtRaw
        : int.tryParse('$updatedAtRaw') ?? 0;
    final typeRaw = (map['type'] ?? '').toString();
    final type = ChatType.values.firstWhere(
      (value) => value.name == typeRaw,
      orElse: () => ChatType.dm,
    );

    final unreadRaw = map['unreadCount'];
    final unreadCount = unreadRaw is int
        ? unreadRaw
        : int.tryParse('$unreadRaw') ?? 0;

    final isInvitedRaw = map['isInvited'];
    final isInvited = isInvitedRaw == true;

    return ChatThread(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        updatedAtMs > 0 ? updatedAtMs : DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ),
      lastMessage: map['lastMessage']?.toString(),
      unreadCount: unreadCount,
      avatarUrl: map['avatarUrl']?.toString(),
      type: type,
      isInvited: isInvited,
    );
  }

  Map<String, dynamic> _messageToMap(ChatMessage message) {
    return <String, dynamic>{
      'id': message.id,
      'roomId': message.roomId,
      'senderId': message.senderId,
      'senderName': message.senderName,
      'body': message.body,
      'kind': message.kind.name,
      'createdAtMs': message.createdAt.millisecondsSinceEpoch,
      'replyToEventId': message.replyToEventId,
      'replyToSenderName': message.replyToSenderName,
      'replyToBody': message.replyToBody,
      'isEdited': message.isEdited,
      'readCount': message.readCount,
      'metadata': message.metadata,
    };
  }

  Map<String, dynamic> _participantToMap(ChatParticipant participant) {
    return <String, dynamic>{
      'userId': participant.userId,
      'displayName': participant.displayName,
      'level': participant.level.name,
      'membership': participant.membership,
      'avatarUrl': participant.avatarUrl,
    };
  }

  ChatParticipant _participantFromMap(Map<String, dynamic> map) {
    final levelRaw = (map['level'] ?? '').toString();
    final level = ChatMemberLevel.values.firstWhere(
      (value) => value.name == levelRaw,
      orElse: () => ChatMemberLevel.member,
    );

    return ChatParticipant(
      userId: (map['userId'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      level: level,
      membership: (map['membership'] ?? '').toString(),
      avatarUrl: map['avatarUrl']?.toString(),
    );
  }

  ChatMessage _messageFromMap(Map<String, dynamic> map) {
    final createdAtRaw = map['createdAtMs'];
    final createdAtMs = createdAtRaw is int
        ? createdAtRaw
        : int.tryParse('$createdAtRaw') ?? 0;
    final kindRaw = (map['kind'] ?? '').toString();
    final kind = MessageKind.values.firstWhere(
      (value) => value.name == kindRaw,
      orElse: () => MessageKind.text,
    );
    final readCountRaw = map['readCount'];
    final readCount = readCountRaw is int
        ? readCountRaw
        : int.tryParse('$readCountRaw') ?? 0;
    final metadataRaw = map['metadata'];
    final metadata = metadataRaw is Map
        ? metadataRaw.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};

    return ChatMessage(
      id: (map['id'] ?? '').toString(),
      roomId: (map['roomId'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      senderName: (map['senderName'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      kind: kind,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAtMs > 0 ? createdAtMs : DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ),
      replyToEventId: map['replyToEventId']?.toString(),
      replyToSenderName: map['replyToSenderName']?.toString(),
      replyToBody: map['replyToBody']?.toString(),
      isEdited: map['isEdited'] == true,
      readCount: readCount,
      metadata: metadata,
    );
  }
}
