// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Post _$PostFromJson(Map<String, dynamic> json) => Post(
  uid: json['uid'] as String?,
  userUid: json['userUid'] as String,
  type: $enumDecode(_$PostTypeEnumMap, json['type']),
  refUid: json['refUid'] as String,
  text: json['text'] as String?,
  timestamp: IsoDateTime.fromJson(json['timestamp'] as String),
  gallery: (json['gallery'] as List<dynamic>)
      .map((e) => GalleryImage.fromJson(e as Map<String, dynamic>))
      .toList(),
  galleryCollageUrl: json['galleryCollageUrl'] as String?,
);

Map<String, dynamic> _$PostToJson(Post instance) => <String, dynamic>{
  'uid': instance.uid,
  'type': _$PostTypeEnumMap[instance.type]!,
  'refUid': instance.refUid,
  'userUid': instance.userUid,
  'text': instance.text,
  'gallery': instance.gallery,
  'galleryCollageUrl': instance.galleryCollageUrl,
  'timestamp': instance.timestamp,
};

const _$PostTypeEnumMap = {
  PostType.clubPost: 'clubPost',
  PostType.eventDatePost: 'eventDatePost',
};

PostEntity _$PostEntityFromJson(Map<String, dynamic> json) =>
    PostEntity(
        uid: json['uid'] as String,
        text: json['text'] as String?,
        timestamp: IsoDateTime.fromJson(json['timestamp'] as String),
        type: $enumDecode(_$PostTypeEnumMap, json['type']),
        refUid: json['refUid'] as String,
        galleryCollageUrl: json['galleryCollageUrl'] as String?,
        user: UserEntity.fromJson(json['user'] as Map<String, dynamic>),
        eventDate: json['eventDate'] == null
            ? null
            : EventDateEntity.fromJson(
                json['eventDate'] as Map<String, dynamic>,
              ),
        club: json['club'] == null
            ? null
            : ClubEntity.fromJson(json['club'] as Map<String, dynamic>),
        countLikes: (json['countLikes'] as num?)?.toInt() ?? 0,
        countViews: (json['countViews'] as num?)?.toInt() ?? 0,
        countComments: (json['countComments'] as num?)?.toInt() ?? 0,
      )
      ..comments = (json['comments'] as List<dynamic>?)
          ?.map((e) => CommentEntity.fromJson(e as Map<String, dynamic>))
          .toList()
      ..likes = (json['likes'] as List<dynamic>?)
          ?.map((e) => UserEntity.fromJson(e as Map<String, dynamic>))
          .toList();

Map<String, dynamic> _$PostEntityToJson(PostEntity instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'text': instance.text,
      'galleryCollageUrl': instance.galleryCollageUrl,
      'type': _$PostTypeEnumMap[instance.type]!,
      'refUid': instance.refUid,
      'timestamp': instance.timestamp,
      'user': instance.user,
      'eventDate': instance.eventDate,
      'club': instance.club,
      'comments': instance.comments,
      'likes': instance.likes,
      'countLikes': instance.countLikes,
      'countComments': instance.countComments,
      'countViews': instance.countViews,
    };

PostDTO _$PostDTOFromJson(Map<String, dynamic> json) => PostDTO(
  post: Post.fromJson(json['post'] as Map<String, dynamic>),
  postEntity: PostEntity.fromJson(json['postEntity'] as Map<String, dynamic>),
);

Map<String, dynamic> _$PostDTOToJson(PostDTO instance) => <String, dynamic>{
  'post': instance.post,
  'postEntity': instance.postEntity,
};

PostGalleryDTO _$PostGalleryDTOFromJson(Map<String, dynamic> json) =>
    PostGalleryDTO(
      postUid: json['postUid'] as String,
      userUid: json['userUid'] as String,
      gallery: (json['gallery'] as List<dynamic>)
          .map((e) => GalleryImage.fromJson(e as Map<String, dynamic>))
          .toList(),
      galleryCollageUrl: json['galleryCollageUrl'] as String?,
      deletedImages: (json['deletedImages'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$PostGalleryDTOToJson(PostGalleryDTO instance) =>
    <String, dynamic>{
      'postUid': instance.postUid,
      'userUid': instance.userUid,
      'gallery': instance.gallery,
      'galleryCollageUrl': instance.galleryCollageUrl,
      'deletedImages': instance.deletedImages,
    };

LikeRequestDTO _$LikeRequestDTOFromJson(Map<String, dynamic> json) =>
    LikeRequestDTO(
      postUid: json['postUid'] as String,
      userUid: json['userUid'] as String,
      like: json['like'] as bool,
    );

Map<String, dynamic> _$LikeRequestDTOToJson(LikeRequestDTO instance) =>
    <String, dynamic>{
      'postUid': instance.postUid,
      'userUid': instance.userUid,
      'like': instance.like,
    };

LikeResponseDTO _$LikeResponseDTOFromJson(Map<String, dynamic> json) =>
    LikeResponseDTO(
      postUid: json['postUid'] as String,
      userUid: json['userUid'] as String,
      likes: (json['likes'] as List<dynamic>?)
          ?.map((e) => UserEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      countLikes: (json['countLikes'] as num).toInt(),
    );

Map<String, dynamic> _$LikeResponseDTOToJson(LikeResponseDTO instance) =>
    <String, dynamic>{
      'postUid': instance.postUid,
      'userUid': instance.userUid,
      'likes': instance.likes,
      'countLikes': instance.countLikes,
    };
