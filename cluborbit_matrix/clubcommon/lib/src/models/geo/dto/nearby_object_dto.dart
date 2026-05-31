import 'package:clubcommon/src/models/common/activity.dart';
import 'package:clubcommon/src/models/common/iso_datetime.dart';
import 'package:clubcommon/src/models/event/event_snippet.dart';
import 'package:json_annotation/json_annotation.dart';

part 'nearby_object_dto.g.dart';

enum MappingType { club, group, clubEvent, groupEvent }

enum MemberType { admin, member, none }

enum NearbyFilter { all, clubs, groups, events }

class Position {
  final double latitude;
  final double longitude;

  Position({required this.latitude, required this.longitude});
}

@JsonSerializable()
class NearbyObjectDTO {
  String uid;

  String name;

  double latitude;

  double longitude;

  double distance;

  MappingType type;

  String? primaryImage;

  String? subImage;

  String? text;

  int? userCount;

  int maxUsers;

  MemberType memberType;

  EventUserStatus? eventUserStatusType;

  List<String?>? relations;

  List<ActivityEntity>? activities;

  IsoDateTime? startDateTime;

  IsoDateTime? endDateTime;

  NearbyObjectDTO({
    required this.uid,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.type,
    required this.maxUsers,
    required this.memberType,
    this.text,
    this.primaryImage,
    this.subImage,
    this.userCount,
    this.eventUserStatusType,
    this.relations,
    this.activities,
    this.startDateTime,
    this.endDateTime,
  });

  factory NearbyObjectDTO.fromJson(Map<String, dynamic> json) =>
      _$NearbyObjectDTOFromJson(json);

  Map<String, dynamic> toJson() => _$NearbyObjectDTOToJson(this);
}
