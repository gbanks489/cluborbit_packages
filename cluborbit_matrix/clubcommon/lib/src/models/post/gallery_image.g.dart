// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gallery_image.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GalleryImage _$GalleryImageFromJson(Map<String, dynamic> json) => GalleryImage(
  uid: json['uid'] as String,
  id: json['id'] as String,
  type: $enumDecode(_$ImageTypeEnumMap, json['type']),
  index: (json['index'] as num).toInt(),
  context: $enumDecode(_$ImageContextEnumMap, json['context']),
  imageEntity: json['imageEntity'] == null
      ? null
      : ImageEntity.fromJson(json['imageEntity'] as Map<String, dynamic>),
  description: json['description'] as String?,
  title: json['title'] as String?,
);

Map<String, dynamic> _$GalleryImageToJson(GalleryImage instance) =>
    <String, dynamic>{
      'index': instance.index,
      'id': instance.id,
      'imageEntity': instance.imageEntity,
      'description': instance.description,
      'title': instance.title,
      'uid': instance.uid,
      'type': _$ImageTypeEnumMap[instance.type]!,
      'context': _$ImageContextEnumMap[instance.context]!,
    };

const _$ImageTypeEnumMap = {
  ImageType.png: 'png',
  ImageType.gif: 'gif',
  ImageType.bmp: 'bmp',
  ImageType.jpg: 'jpg',
  ImageType.ico: 'ico',
  ImageType.tiff: 'tiff',
  ImageType.webP: 'webP',
  ImageType.heifHeic: 'heifHeic',
  ImageType.unknown: 'unknown',
};

const _$ImageContextEnumMap = {
  ImageContext.galleryThumbnail: 'galleryThumbnail',
  ImageContext.galleryImage: 'galleryImage',
  ImageContext.galleryCollage: 'galleryCollage',
  ImageContext.profilePic: 'profilePic',
  ImageContext.eventPic: 'eventPic',
  ImageContext.eventPicThumbnail: 'eventPicThumbnail',
  ImageContext.coverImagePic: 'coverImagePic',
  ImageContext.profilePicThumbnail: 'profilePicThumbnail',
  ImageContext.clubThumbnail: 'clubThumbnail',
  ImageContext.clubPic: 'clubPic',
  ImageContext.originalSize: 'originalSize',
};
