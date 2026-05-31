import 'package:clubcommon/src/models/common/image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:json_annotation/json_annotation.dart';

part 'gallery_image.g.dart';

class ImageSize {
  final int height;
  final int width;

  ImageSize({required this.height, required this.width});
}

enum ImageContext {
  galleryThumbnail,
  galleryImage,
  galleryCollage,
  profilePic,
  eventPic,
  eventPicThumbnail,
  coverImagePic,
  profilePicThumbnail,
  clubThumbnail,
  clubPic,
  originalSize,
}

enum ImageType { png, gif, bmp, jpg, ico, tiff, webP, heifHeic, unknown }

class MaxImageSizes {
  Map<ImageContext, ImageSize> sizes = {};

  MaxImageSizes();

  void addImageSize(ImageContext label, height, width) {
    ImageSize size = ImageSize(height: height, width: width);

    sizes[label] = size;
  }
}

@JsonSerializable()
class GalleryImage {
  GalleryImage({
    required this.uid,
    required this.id,
    required this.type,
    required this.index,
    required this.context,
    this.imageEntity,
    this.xFile,
    this.description,
    this.title,
  });
  // index in list of image
  int index;
  // id image (image url) to use in hero animation
  final String id;

  ImageEntity? imageEntity;

  String? description;

  @JsonKey(includeFromJson: false)
  //Uint8List? imageBytes;
  XFile? xFile;

  String? title;

  String uid;

  //ImageInfo info;

  ImageType type;

  ImageContext context;

  static ImageType getTypeFromString(String name) {
    ImageType type = ImageType.unknown;

    List<String> idSplit = name.split(".");
    String? format = (idSplit.length >= 2) ? idSplit[idSplit.length - 1] : null;

    switch (format) {
      case "jpg":
        type = ImageType.jpg;
        break;
      case "png":
        type = ImageType.png;
        break;
      case "gif":
        type = ImageType.gif;
        break;
      case "bmp":
        type = ImageType.bmp;
        break;
      case "Ico":
        type = ImageType.ico;
        break;
      default:
        type = ImageType.unknown;
    }

    return type;
  }

  String getPath() {
    return path;
  }

  factory GalleryImage.fromJson(Map<String, dynamic> json) =>
      _$GalleryImageFromJson(json);

  Map<String, dynamic> toJson() => _$GalleryImageToJson(this);

  static String get path => "galleryImage";
}
