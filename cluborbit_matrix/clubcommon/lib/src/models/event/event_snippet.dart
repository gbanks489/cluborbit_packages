import 'package:clubcommon/src/models/common/iso_datetime.dart';
import 'package:json_annotation/json_annotation.dart';

part 'event_snippet.g.dart';

enum EventUserStatus { going, waitlisted, notGoing, administers }

@JsonSerializable()
class EventSeriesUserRelationship {
  String uid;
  String eventSeriesUid;
  String userUid;
  EventUserStatus? eventUserStatus;

  EventSeriesUserRelationship({
    required this.uid,
    required this.eventSeriesUid,
    this.eventUserStatus,
    required this.userUid,
  });

  String getPath() {
    return path;
  }

  factory EventSeriesUserRelationship.fromJson(Map<String, dynamic> json) =>
      _$EventSeriesUserRelationshipFromJson(json);

  Map<String, dynamic> toJson() => _$EventSeriesUserRelationshipToJson(this);

  static String get path => "eventSeriesUserRelationship";
}

@JsonSerializable()
class EventSeriesUserRelationshipDTO {
  String uid;
  String eventSeriesUid;
  String userUid;
  EventUserStatus? eventUserStatus;
  String? userProfilePicUrl;
  String userDisplayName;
  IsoDateTime? timestamp;

  EventSeriesUserRelationshipDTO({
    required this.uid,
    required this.eventSeriesUid,
    this.eventUserStatus,
    required this.userUid,
    this.userProfilePicUrl,
    required this.userDisplayName,
    this.timestamp,
  });

  String getPath() {
    return path;
  }

  factory EventSeriesUserRelationshipDTO.fromJson(Map<String, dynamic> json) =>
      _$EventSeriesUserRelationshipDTOFromJson(json);

  Map<String, dynamic> toJson() => _$EventSeriesUserRelationshipDTOToJson(this);

  static String get path => "eventSeriesUserRelationship";
}
