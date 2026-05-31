/* class PlacePhotos {
  List<PlacePhoto> placePhotos;
 
  PlacePhotos({
    required this.placePhotos});

  factory PlacePhotos.fromJson(Map<String,dynamic> json){
    return PlacePhoto(
        photoReference: json['description']
    );
  }
} */

class PlacePhoto {
  final String photoReference;
  
  PlacePhoto({
    required this.photoReference});

  factory PlacePhoto.fromJson(Map<String,dynamic> json){
    return PlacePhoto(
        photoReference: json['description']
    );
  }
}