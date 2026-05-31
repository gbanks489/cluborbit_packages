// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_action.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EventAction _$EventActionFromJson(Map<String, dynamic> json) => EventAction(
  userUid: json['userUid'] as String,
  eventUid: json['eventUid'] as String,
  eventActionStatus: $enumDecode(
    _$EventActionStatusEnumMap,
    json['eventActionStatus'],
  ),
  updatedTime: DateTime.parse(json['updatedTime'] as String),
);

Map<String, dynamic> _$EventActionToJson(
  EventAction instance,
) => <String, dynamic>{
  'userUid': instance.userUid,
  'eventUid': instance.eventUid,
  'eventActionStatus': _$EventActionStatusEnumMap[instance.eventActionStatus]!,
  'updatedTime': instance.updatedTime.toIso8601String(),
};

const _$EventActionStatusEnumMap = {
  EventActionStatus.going: 'going',
  EventActionStatus.notGoing: 'notGoing',
};
