import 'package:clubcommon/clubcommon.dart';
import 'package:clubcommon/src/models/common/iso_datetime.dart';
import 'package:json_annotation/json_annotation.dart';

part 'post.g.dart';

/*
class PostImageItem {
  PostImageItem({
    required this.uid,
    this.fullResImageUrl,
    this.description,
    this.title,
    this.imageType
  });
  
  // id image (image url) to use in hero animation
  final String uid;
  // image url
  final String? fullResImageUrl;
  final String? title;
  final String? description;
  final ImageType? imageType;

  String getPath() { return path; }

  factory PostImageItem.fromJson(Map<String, dynamic> json) => _$PostImageItemFromJson(json);
  
  Map<String, dynamic> toJson() => _$PostImageItemToJson(this); 

  static String get path => "postImageItems";
} 
*/

@JsonSerializable()
class Post {
  String? uid;
  PostType type;
  String refUid;
  String userUid;
  String? text;
  List<GalleryImage> gallery;
  String? galleryCollageUrl;
  IsoDateTime timestamp;

  //String? adminEventSnippetUid;

  Post({
    this.uid,
    required this.userUid,
    required this.type,
    required this.refUid,
    required this.text,
    required this.timestamp,
    required this.gallery,
    this.galleryCollageUrl,
  });

  //String getPath() { return path; }

  factory Post.fromJson(Map<String, dynamic> json) => _$PostFromJson(json);

  Map<String, dynamic> toJson() => _$PostToJson(this);

  static String get path => "post";
}

enum PostType { clubPost, eventDatePost }

enum PostQueryType { clubPost, eventDatePost, userPost }

Map<PostQueryType, String> postQueryTypes = {
  PostQueryType.clubPost: "clubUid",
  PostQueryType.eventDatePost: "eventDateUid",
  PostQueryType.userPost: "userUid",
};

@JsonSerializable()
class PostEntity {
  String uid;
  String? text;
  String? galleryCollageUrl;
  PostType type;
  String refUid;
  IsoDateTime timestamp;
  UserEntity user;
  EventDateEntity? eventDate;
  ClubEntity? club;
  List<CommentEntity>? comments;
  List<UserEntity>? likes;

  int countLikes;
  final int countComments;
  int countViews;

  //String? adminEventSnippetUid;

  PostEntity({
    required this.uid,
    required this.text,
    required this.timestamp,
    required this.type,
    required this.refUid,
    this.galleryCollageUrl,
    required this.user,
    this.eventDate,
    this.club,
    this.countLikes = 0,
    this.countViews = 0,
    this.countComments = 0,
  });

  factory PostEntity.fromJson(Map<String, dynamic> json) =>
      _$PostEntityFromJson(json);

  Map<String, dynamic> toJson() => _$PostEntityToJson(this);

  static String get path => "post";
}

@JsonSerializable()
class PostDTO {
  final Post post;
  final PostEntity postEntity;

  //String? adminEventSnippetUid;

  const PostDTO({required this.post, required this.postEntity});

  factory PostDTO.fromJson(Map<String, dynamic> json) =>
      _$PostDTOFromJson(json);

  Map<String, dynamic> toJson() => _$PostDTOToJson(this);

  static String get path => "post";
}

@JsonSerializable()
class PostGalleryDTO {
  final String postUid;
  final String userUid;
  final List<GalleryImage> gallery;
  final String? galleryCollageUrl;
  final List<String>? deletedImages;

  const PostGalleryDTO({
    required this.postUid,
    required this.userUid,
    required this.gallery,
    this.galleryCollageUrl,
    this.deletedImages,
  });

  factory PostGalleryDTO.fromJson(Map<String, dynamic> json) =>
      _$PostGalleryDTOFromJson(json);

  Map<String, dynamic> toJson() => _$PostGalleryDTOToJson(this);
}

@JsonSerializable()
class LikeRequestDTO {
  final String postUid;
  final String userUid;
  final bool like;

  const LikeRequestDTO({
    required this.postUid,
    required this.userUid,
    required this.like,
  });

  factory LikeRequestDTO.fromJson(Map<String, dynamic> json) =>
      _$LikeRequestDTOFromJson(json);

  Map<String, dynamic> toJson() => _$LikeRequestDTOToJson(this);

  static String get path => "post";
}

@JsonSerializable()
class LikeResponseDTO {
  final String postUid;
  final String userUid;
  final List<UserEntity>? likes;
  final int countLikes;

  const LikeResponseDTO({
    required this.postUid,
    required this.userUid,
    required this.likes,
    required this.countLikes,
  });

  factory LikeResponseDTO.fromJson(Map<String, dynamic> json) =>
      _$LikeResponseDTOFromJson(json);

  Map<String, dynamic> toJson() => _$LikeResponseDTOToJson(this);

  // static String get path => "post";
}
