import 'package:json_annotation/json_annotation.dart';

part 'image.g.dart';

@JsonSerializable()
class ImageEntity {
  String? thumbnailURL;
  String? scrollSizeURL;
  String? fullSizeURL;
  List<String>? attributions;

  ImageEntity({
    this.thumbnailURL,
    this.scrollSizeURL,
    required this.fullSizeURL,
    this.attributions,
  });

  factory ImageEntity.fromJson(Map<String, dynamic> json) =>
      _$ImageEntityFromJson(json);

  Map<String, dynamic> toJson() => _$ImageEntityToJson(this);
}
