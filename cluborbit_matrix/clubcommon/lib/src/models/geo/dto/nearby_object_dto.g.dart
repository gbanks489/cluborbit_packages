// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nearby_object_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NearbyObjectDTO _$NearbyObjectDTOFromJson(Map<String, dynamic> json) =>
    NearbyObjectDTO(
      uid: json['uid'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      distance: (json['distance'] as num).toDouble(),
      type: $enumDecode(_$MappingTypeEnumMap, json['type']),
      maxUsers: (json['maxUsers'] as num).toInt(),
      memberType: $enumDecode(_$MemberTypeEnumMap, json['memberType']),
      text: json['text'] as String?,
      primaryImage: json['primaryImage'] as String?,
      subImage: json['subImage'] as String?,
      userCount: (json['userCount'] as num?)?.toInt(),
      eventUserStatusType: $enumDecodeNullable(
        _$EventUserStatusEnumMap,
        json['eventUserStatusType'],
      ),
      relations: (json['relations'] as List<dynamic>?)
          ?.map((e) => e as String?)
          .toList(),
      activities: (json['activities'] as List<dynamic>?)
          ?.map((e) => ActivityEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      startDateTime: json['startDateTime'] == null
          ? null
          : IsoDateTime.fromJson(json['startDateTime'] as String),
      endDateTime: json['endDateTime'] == null
          ? null
          : IsoDateTime.fromJson(json['endDateTime'] as String),
    );

Map<String, dynamic> _$NearbyObjectDTOToJson(
  NearbyObjectDTO instance,
) => <String, dynamic>{
  'uid': instance.uid,
  'name': instance.name,
  'latitude': instance.latitude,
  'longitude': instance.longitude,
  'distance': instance.distance,
  'type': _$MappingTypeEnumMap[instance.type]!,
  'primaryImage': instance.primaryImage,
  'subImage': instance.subImage,
  'text': instance.text,
  'userCount': instance.userCount,
  'maxUsers': instance.maxUsers,
  'memberType': _$MemberTypeEnumMap[instance.memberType]!,
  'eventUserStatusType': _$EventUserStatusEnumMap[instance.eventUserStatusType],
  'relations': instance.relations,
  'activities': instance.activities,
  'startDateTime': instance.startDateTime,
  'endDateTime': instance.endDateTime,
};

const _$MappingTypeEnumMap = {
  MappingType.club: 'club',
  MappingType.group: 'group',
  MappingType.clubEvent: 'clubEvent',
  MappingType.groupEvent: 'groupEvent',
};

const _$MemberTypeEnumMap = {
  MemberType.admin: 'admin',
  MemberType.member: 'member',
  MemberType.none: 'none',
};

const _$EventUserStatusEnumMap = {
  EventUserStatus.going: 'going',
  EventUserStatus.waitlisted: 'waitlisted',
  EventUserStatus.notGoing: 'notGoing',
  EventUserStatus.administers: 'administers',
};
