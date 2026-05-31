enum ChatType { dm, group }

enum MessageKind { text, image, video, emoji }

enum ChatMemberLevel { owner, admin, moderator, member }

class ChatParticipant {
  const ChatParticipant({
    required this.userId,
    required this.displayName,
    required this.level,
    required this.membership,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final ChatMemberLevel level;
  final String membership;
  final String? avatarUrl;
}

class ChatUserPresence {
  const ChatUserPresence({
    required this.userId,
    required this.isOnline,
    this.lastActiveAt,
    this.presence = 'offline',
  });

  final String userId;
  final bool isOnline;
  final DateTime? lastActiveAt;
  final String presence;
}

class VerificationSession {
  const VerificationSession({
    required this.id,
    required this.userId,
    required this.state,
    required this.isDone,
  });

  final String id;
  final String userId;
  final String state;
  final bool isDone;
}

class ChatEncryptionStatus {
  const ChatEncryptionStatus({required this.isEncrypted, this.algorithm});

  const ChatEncryptionStatus.unencrypted()
    : isEncrypted = false,
      algorithm = null;

  final bool isEncrypted;
  final String? algorithm;
}

class ChatThread {
  const ChatThread({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.avatarUrl,
    this.type = ChatType.dm,
    this.isInvited = false,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final String? lastMessage;
  final int unreadCount;
  final String? avatarUrl;
  final ChatType type;
  final bool isInvited;

  ChatThread copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    String? lastMessage,
    int? unreadCount,
    String? avatarUrl,
    ChatType? type,
    bool? isInvited,
  }) {
    return ChatThread(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      type: type ?? this.type,
      isInvited: isInvited ?? this.isInvited,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.kind,
    required this.createdAt,
    this.replyToEventId,
    this.replyToSenderName,
    this.replyToBody,
    this.isEdited = false,
    this.readCount = 0,
    this.metadata = const {},
  });

  final String id;
  final String roomId;
  final String senderId;
  final String senderName;
  final String body;
  final MessageKind kind;
  final DateTime createdAt;
  final String? replyToEventId;
  final String? replyToSenderName;
  final String? replyToBody;
  final bool isEdited;
  final int readCount;
  final Map<String, dynamic> metadata;

  ChatMessage copyWith({
    String? id,
    String? roomId,
    String? senderId,
    String? senderName,
    String? body,
    MessageKind? kind,
    DateTime? createdAt,
    String? replyToEventId,
    String? replyToSenderName,
    String? replyToBody,
    bool? isEdited,
    int? readCount,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      body: body ?? this.body,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
      replyToEventId: replyToEventId ?? this.replyToEventId,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      replyToBody: replyToBody ?? this.replyToBody,
      isEdited: isEdited ?? this.isEdited,
      readCount: readCount ?? this.readCount,
      metadata: metadata ?? this.metadata,
    );
  }
}
