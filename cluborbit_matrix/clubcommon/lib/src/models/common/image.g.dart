// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImageEntity _$ImageEntityFromJson(Map<String, dynamic> json) => ImageEntity(
  thumbnailURL: json['thumbnailURL'] as String?,
  scrollSizeURL: json['scrollSizeURL'] as String?,
  fullSizeURL: json['fullSizeURL'] as String?,
  attributions: (json['attributions'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$ImageEntityToJson(ImageEntity instance) =>
    <String, dynamic>{
      'thumbnailURL': instance.thumbnailURL,
      'scrollSizeURL': instance.scrollSizeURL,
      'fullSizeURL': instance.fullSizeURL,
      'attributions': instance.attributions,
    };
