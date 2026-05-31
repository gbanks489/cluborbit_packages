// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_snippet.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EventSeriesUserRelationship _$EventSeriesUserRelationshipFromJson(
  Map<String, dynamic> json,
) => EventSeriesUserRelationship(
  uid: json['uid'] as String,
  eventSeriesUid: json['eventSeriesUid'] as String,
  eventUserStatus: $enumDecodeNullable(
    _$EventUserStatusEnumMap,
    json['eventUserStatus'],
  ),
  userUid: json['userUid'] as String,
);

Map<String, dynamic> _$EventSeriesUserRelationshipToJson(
  EventSeriesUserRelationship instance,
) => <String, dynamic>{
  'uid': instance.uid,
  'eventSeriesUid': instance.eventSeriesUid,
  'userUid': instance.userUid,
  'eventUserStatus': _$EventUserStatusEnumMap[instance.eventUserStatus],
};

const _$EventUserStatusEnumMap = {
  EventUserStatus.going: 'going',
  EventUserStatus.waitlisted: 'waitlisted',
  EventUserStatus.notGoing: 'notGoing',
  EventUserStatus.administers: 'administers',
};

EventSeriesUserRelationshipDTO _$EventSeriesUserRelationshipDTOFromJson(
  Map<String, dynamic> json,
) => EventSeriesUserRelationshipDTO(
  uid: json['uid'] as String,
  eventSeriesUid: json['eventSeriesUid'] as String,
  eventUserStatus: $enumDecodeNullable(
    _$EventUserStatusEnumMap,
    json['eventUserStatus'],
  ),
  userUid: json['userUid'] as String,
  userProfilePicUrl: json['userProfilePicUrl'] as String?,
  userDisplayName: json['userDisplayName'] as String,
  timestamp: json['timestamp'] == null
      ? null
      : IsoDateTime.fromJson(json['timestamp'] as String),
);

Map<String, dynamic> _$EventSeriesUserRelationshipDTOToJson(
  EventSeriesUserRelationshipDTO instance,
) => <String, dynamic>{
  'uid': instance.uid,
  'eventSeriesUid': instance.eventSeriesUid,
  'userUid': instance.userUid,
  'eventUserStatus': _$EventUserStatusEnumMap[instance.eventUserStatus],
  'userProfilePicUrl': instance.userProfilePicUrl,
  'userDisplayName': instance.userDisplayName,
  'timestamp': instance.timestamp,
};
