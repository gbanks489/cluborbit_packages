import 'package:clubcommon/clubcommon.dart';
import 'package:clubcommon/src/models/common/iso_datetime.dart';
import 'package:clubcommon/src/models/user/user.dart';
import 'package:json_annotation/json_annotation.dart';

part 'comment.g.dart';

@JsonSerializable()
class Comment {
  String? uid;
  String userUid;
  IsoDateTime? timestamp;
  String text;
  String postUid;
  String? parentCommentUid;

  //String? adminEventSnippetUid;

  Comment({
    this.uid,
    required this.userUid,
    this.timestamp,
    required this.text,
    required this.postUid,
    this.parentCommentUid,
  });

  //String getPath() { return path; }

  factory Comment.fromJson(Map<String, dynamic> json) =>
      _$CommentFromJson(json);

  Map<String, dynamic> toJson() => _$CommentToJson(this);

  static String get path => "comment";
}

@JsonSerializable()
class CommentEntity {
  String uid;
  UserEntity? user;
  IsoDateTime timestamp;
  String text;
  CommentEntity? parentComment;
  List<CommentEntity>? replies;

  List<UserEntity>? likes;
  int countLikes;

  //String? adminEventSnippetUid;

  CommentEntity({
    required this.uid,
    required this.text,
    required this.timestamp,
    this.user,
    this.parentComment,
    this.replies,
    this.countLikes = 0,
  });

  factory CommentEntity.fromJson(Map<String, dynamic> json) =>
      _$CommentEntityFromJson(json);

  Map<String, dynamic> toJson() => _$CommentEntityToJson(this);

  static String get path => "post";

  get name => null;
}
