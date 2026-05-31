
import 'core.dart';

class Place {
  final Geometry geometry;
  final String name;
  final String vicinity;
  final String formattedAddress; 
  final String uri;


  Place({required this.geometry,
         required this.name,
         required this.vicinity,
         required this.formattedAddress,
         required this.uri});

  factory Place.fromJson(Map<String,dynamic> json){
    return Place(
        geometry:  Geometry.fromJson(json['geometry']),
        formattedAddress: json['formatted_address'],
        name: json["name"],
        uri: json["url"],
        vicinity: json['vicinity'],
    );
  }
}