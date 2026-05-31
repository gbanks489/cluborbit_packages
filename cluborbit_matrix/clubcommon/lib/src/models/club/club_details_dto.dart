import 'package:clubcommon/clubcommon.dart';
import 'package:clubcommon/src/models/common/activity.dart';
import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

part 'club_details_dto.g.dart';

@JsonSerializable()
class ClubEntity {
  String uid;
  String name;
  String formattedAddress;
  String? shortAddress;
  String? profilePicUrl;
  String? profilePicUrlScroll;
  String placeId;
  int memberCount;
  int viewCount;
  List<ActivityEntity>? activities;
  List<ClubEntity>? groups;
  ClubEntity? hostClub;
  String? about;
  bool? aiGenerated;
  ClubType? type;
  double? lat;
  double? lng;
  double? distance;
  UserEntity? adminProfile;

  final List<MembershipEntity>? memberships;

  ClubEntity({
    required this.uid,
    required this.name,
    required this.placeId,
    required this.memberCount,
    required this.viewCount,
    this.profilePicUrl,
    required this.formattedAddress,
    this.shortAddress,
    this.activities,
    this.about,
    this.aiGenerated,
    this.adminProfile,
    this.groups,
    this.hostClub,
    this.type,
    this.lat,
    this.lng,
    this.distance,
    required this.memberships,
  });

  String getFormattedDistance() {
    if (distance != null) {
      double d = distance! / 1000.0;

      if (d < 1) {
        return "${NumberFormat('##0').format(d * 1000)} m";
      } else if (d < 10) {
        return "${NumberFormat('#,##0.0').format(d)} km";
      } else {
        return "${NumberFormat('#,##0').format(d)} km";
      }
    }

    return "0 km";
  }

  factory ClubEntity.fromJson(Map<String, dynamic> json) =>
      _$ClubEntityFromJson(json);

  Map<String, dynamic> toJson() => _$ClubEntityToJson(this);
}

@JsonSerializable()
class ClubSnippetDTO {
  final String name;
  final String formattedAddress;
  final String? profilePicUrl;
  final String uid;
  final int memberCount;
  final String userRole;
  final List<ActivityEntity>? activities;

  ClubSnippetDTO({
    required this.name,
    required this.formattedAddress,
    this.profilePicUrl,
    required this.uid,
    required this.memberCount,
    this.activities,
    required this.userRole,
  });

  factory ClubSnippetDTO.fromJson(Map<String, dynamic> json) =>
      _$ClubSnippetDTOFromJson(json);

  Map<String, dynamic> toJson() => _$ClubSnippetDTOToJson(this);
}

@JsonSerializable()
class ClubDetailsDTO {
  Club? club;
  ClubEntity? clubEntity;
  Club? hostClub;
  UserProfileSnippet? adminProfile;
  final ClubAnalytics? analytics;
  final List<MembershipEntity>? memberships;
  final List<EventSeriesSummaryDTO>? eventSeries;
  final List<ClubEntity>? groups;
  List<ActivityEntity>? activities;

  ClubDetailsDTO({
    required this.club,
    this.analytics,
    this.memberships,
    this.eventSeries,
    this.activities,
    this.groups,
  });

  factory ClubDetailsDTO.fromJson(Map<String, dynamic> json) =>
      _$ClubDetailsDTOFromJson(json);

  Map<String, dynamic> toJson() => _$ClubDetailsDTOToJson(this);
}

/*
@JsonSerializable()
class MembershipDTO {
  final String userUid;
  final String? profilePicUrl;

  MembershipDTO({ required this.userUid, 
                  this.profilePicUrl });

  factory MembershipDTO.fromJson(Map<String, dynamic> json) => _$MembershipDTOFromJson(json);

  Map<String, dynamic> toJson() => _$MembershipDTOToJson(this);
} */
