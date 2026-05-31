import 'package:clubcommon/src/models/common/activity.dart';
import 'package:clubcommon/src/models/common/image.dart';
import 'package:clubcommon/src/models/feed/activity_feed.dart';
import 'package:clubcommon/src/models/geo/core.dart';
import 'package:clubcommon/src/models/geo/dto/nearby_object_dto.dart';
import 'package:clubcommon/src/models/geo/places.dart';
import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

/// This allows the `User` class to access private members in
/// the generated file. The value for this is *.g.dart, where
/// the star denotes the source file name.
part 'club.g.dart';

abstract class DataObject<T> {
  final String path = "";

  String getPath();

  Map<String, dynamic> toJson();

  //DataObject<T> fromMap(Map snapshot);
}

enum RelationshipType { member, guest }

/*
@JsonSerializable()
class UserRelationship {
  final String userUid;
  RelationshipType relationshipType;
  bool verified; 
  String? profilePicUrl;

  UserRelationship({
    required this.userUid,
    required this.relationshipType,
    required this.verified,
    required this.profilePicUrl
  });  

  factory UserRelationship.fromJson(Map<String, dynamic> json) => _$UserRelationshipFromJson(json);

  Map<String, dynamic> toJson() => _$UserRelationshipToJson(this);
} */

enum ClubType { club, group }

@JsonSerializable()
class ClubAnalytics {
  final int? memberCount;
  final int? faciiities;
  final int? pastEventCount;
  final int? futureEventCount;

  ClubAnalytics({
    this.memberCount,
    this.faciiities,
    this.pastEventCount,
    this.futureEventCount,
  });

  factory ClubAnalytics.fromJson(Map<String, dynamic> json) =>
      _$ClubAnalyticsFromJson(json);

  Map<String, dynamic> toJson() => _$ClubAnalyticsToJson(this);
}

@JsonSerializable()
class ClubUser {
  final String userUid;

  final Club club;

  ClubUser({required this.userUid, required this.club});

  factory ClubUser.fromJson(Map<String, dynamic> json) =>
      _$ClubUserFromJson(json);

  Map<String, dynamic> toJson() => _$ClubUserToJson(this);
}

enum UserClubRelationshipType { belongs, admin }

@JsonSerializable()
class UserClubRelationship {
  final String userUid;

  final String clubUid;

  final String? relationshipUid;

  final UserClubRelationshipType type;

  UserClubRelationship({
    required this.userUid,
    required this.clubUid,
    required this.type,
    this.relationshipUid,
  });

  factory UserClubRelationship.fromJson(Map<String, dynamic> json) =>
      _$UserClubRelationshipFromJson(json);

  Map<String, dynamic> toJson() => _$UserClubRelationshipToJson(this);
}

//

@JsonSerializable()
class AiClubResponse {
  final String? bio;
  List<Activity>? activities;

  AiClubResponse({this.bio, this.activities});

  factory AiClubResponse.fromJson(Map<String, dynamic> json) =>
      _$AiClubResponseFromJson(json);

  Map<String, dynamic> toJson() => _$AiClubResponseToJson(this);
}

@JsonSerializable()
class Club {
  final String placeId;
  final String name;
  final ClubType clubType;

  String formattedAddress;
  Location? location;
  String? staticMapUrl;
  String? uid;

  //@JsonKey(disallowNullValue: true)

  String? phoneNumber;
  String? website;
  ImageEntity? profilePic;
  String? coverPicUrl;
  List<String>? coverPicAttributions;
  String? about;
  bool? aiGenerated;
  String? shortAddress;
  String? adminUid;
  String? masterClubUid;

  @JsonKey(includeFromJson: true, includeToJson: false)
  double? distance;
  bool isPrivate;
  String? roomAlias;

  //@JsonKey(disallowNullValue: true)
  List<String>? activities;
  //Map<String, UserRelationship>?   userRelationships;

  Club({
    required this.uid,
    required this.name,
    required this.placeId,
    required this.formattedAddress,
    required this.clubType,
    required this.isPrivate,
    this.masterClubUid,
    this.shortAddress,
    this.location,
    this.roomAlias,
    //   this.adminProfile,
    this.adminUid,
    this.phoneNumber,
    this.website,
    this.profilePic,
    this.coverPicUrl,
    this.about,
    this.aiGenerated,
    this.staticMapUrl,
    //  required this.userRelationships,
    this.activities,
    this.distance,
    this.coverPicAttributions,
  });

  String getPath() {
    return "club";
  }

  factory Club.fromJson(Map<String, dynamic> json) => _$ClubFromJson(json);

  Map<String, dynamic> toJson() => _$ClubToJson(this);

  String getFormattedDistance() {
    return Club.getDistanceAsString(distance);
  }

  static String getDistanceAsString(double? distance) {
    if (distance != null) {
      double d = distance / 1000.0;

      if (d < 1) {
        return "${NumberFormat('##0').format(d * 1000)} m";
      } else if (d < 10) {
        return "${NumberFormat('#,##0.0').format(d)} km";
      } else {
        return "${NumberFormat('#,##0').format(d)} km";
      }
    }

    return "";
  }

  static String? getShortAddress(List<AddressComponent> addressComponents) {
    String? administrativeAreaLevel1;
    String? administrativeAreaLevel2;
    String? administrativeAreaLevel3;
    String? administrativeAreaLevel4;
    String? administrativeAreaLevel1Long;

    for (AddressComponent component in addressComponents) {
      for (String type in component.types) {
        if (type.compareTo("administrative_area_level_1") == 0) {
          administrativeAreaLevel1 = component.short_name;
          administrativeAreaLevel1Long = component.long_name;
        } else if (type.compareTo("administrative_area_level_2") == 0) {
          administrativeAreaLevel2 = component.long_name;
        } else if (type.compareTo("administrative_area_level_3") == 0) {
          administrativeAreaLevel3 = component.long_name;
        } else if (type.compareTo("administrative_area_level_4") == 0) {
          administrativeAreaLevel4 = component.long_name;
        }
      }
    }

    String? lowestLevel;
    if (administrativeAreaLevel4 != null) {
      lowestLevel = administrativeAreaLevel4;
    } else if (administrativeAreaLevel3 != null) {
      lowestLevel = administrativeAreaLevel3;
    } else if (administrativeAreaLevel2 != null) {
      lowestLevel = administrativeAreaLevel2;
    }

    if (administrativeAreaLevel1 != null && lowestLevel != null) {
      return "$lowestLevel, $administrativeAreaLevel1";
    } else if (administrativeAreaLevel1 != null) {
      return "$administrativeAreaLevel1Long";
    } else if (lowestLevel != null) {
      return lowestLevel;
    }

    return null;
  }

  static Club? fromPlaceDetails(
    PlaceDetails? placeDetails,
    ImageEntity? profilePic,
    String? coverPicUrl,
    List<String>? coverPicAttributions,
    String? staticMapUrl,
    Position? myLocation,
  ) {
    if (placeDetails != null) {
      Geometry? geometry = placeDetails.geometry;
      Location? location = (geometry != null) ? geometry.location : null;

      return Club(
        placeId: placeDetails.placeId,
        uid: null,
        isPrivate: false,
        phoneNumber: placeDetails.internationalPhoneNumber,
        clubType: ClubType.club,
        website: placeDetails.website,
        name: placeDetails.name,
        location: location,
        formattedAddress: placeDetails.formattedAddress!,
        shortAddress: Club.getShortAddress(placeDetails.addressComponents),
        adminUid: null,
        activities: const [],
        //    userRelationships: <String, UserRelationship>{},
        profilePic: profilePic,
        coverPicUrl: coverPicUrl,
        coverPicAttributions: coverPicAttributions,
        staticMapUrl: staticMapUrl,
        distance: placeDetails.geometry != null
            ? DistanceDTO.calculateDistance(
                location?.lat ?? 0,
                location?.lng ?? 0,
                myLocation?.latitude ?? 0,
                myLocation?.longitude ?? 0,
              )
            : null,
      );
    } else {
      return null;
    }
  }
}
