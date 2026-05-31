// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Comment _$CommentFromJson(Map<String, dynamic> json) => Comment(
  uid: json['uid'] as String?,
  userUid: json['userUid'] as String,
  timestamp: json['timestamp'] == null
      ? null
      : IsoDateTime.fromJson(json['timestamp'] as String),
  text: json['text'] as String,
  postUid: json['postUid'] as String,
  parentCommentUid: json['parentCommentUid'] as String?,
);

Map<String, dynamic> _$CommentToJson(Comment instance) => <String, dynamic>{
  'uid': instance.uid,
  'userUid': instance.userUid,
  'timestamp': instance.timestamp,
  'text': instance.text,
  'postUid': instance.postUid,
  'parentCommentUid': instance.parentCommentUid,
};

CommentEntity _$CommentEntityFromJson(Map<String, dynamic> json) =>
    CommentEntity(
        uid: json['uid'] as String,
        text: json['text'] as String,
        timestamp: IsoDateTime.fromJson(json['timestamp'] as String),
        user: json['user'] == null
            ? null
            : UserEntity.fromJson(json['user'] as Map<String, dynamic>),
        parentComment: json['parentComment'] == null
            ? null
            : CommentEntity.fromJson(
                json['parentComment'] as Map<String, dynamic>,
              ),
        replies: (json['replies'] as List<dynamic>?)
            ?.map((e) => CommentEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
        countLikes: (json['countLikes'] as num?)?.toInt() ?? 0,
      )
      ..likes = (json['likes'] as List<dynamic>?)
          ?.map((e) => UserEntity.fromJson(e as Map<String, dynamic>))
          .toList();

Map<String, dynamic> _$CommentEntityToJson(CommentEntity instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'user': instance.user,
      'timestamp': instance.timestamp,
      'text': instance.text,
      'parentComment': instance.parentComment,
      'replies': instance.replies,
      'likes': instance.likes,
      'countLikes': instance.countLikes,
    };
