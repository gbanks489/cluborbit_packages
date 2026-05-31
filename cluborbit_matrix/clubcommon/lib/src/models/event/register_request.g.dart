// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'register_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RegisterRequest _$RegisterRequestFromJson(Map<String, dynamic> json) =>
    RegisterRequest(
      eventSeriesUid: json['eventSeriesUid'] as String,
      userUid: json['userUid'] as String,
      eventUserStatus: $enumDecode(
        _$EventUserStatusEnumMap,
        json['eventUserStatus'],
      ),
    );

Map<String, dynamic> _$RegisterRequestToJson(RegisterRequest instance) =>
    <String, dynamic>{
      'eventSeriesUid': instance.eventSeriesUid,
      'userUid': instance.userUid,
      'eventUserStatus': _$EventUserStatusEnumMap[instance.eventUserStatus]!,
    };

const _$EventUserStatusEnumMap = {
  EventUserStatus.going: 'going',
  EventUserStatus.waitlisted: 'waitlisted',
  EventUserStatus.notGoing: 'notGoing',
  EventUserStatus.administers: 'administers',
};

RegisterResponse _$RegisterResponseFromJson(Map<String, dynamic> json) =>
    RegisterResponse(
      status: $enumDecode(_$EventUserStatusEnumMap, json['status']),
      numberPeopleWaitlisted: (json['numberPeopleWaitlisted'] as num).toInt(),
      numberPeopleGoing: (json['numberPeopleGoing'] as num).toInt(),
      maxPeople: (json['maxPeople'] as num).toInt(),
      registeredProfilePics: (json['registeredProfilePics'] as List<dynamic>?)
          ?.map((e) => e as String?)
          .toList(),
    );

Map<String, dynamic> _$RegisterResponseToJson(RegisterResponse instance) =>
    <String, dynamic>{
      'status': _$EventUserStatusEnumMap[instance.status]!,
      'numberPeopleWaitlisted': instance.numberPeopleWaitlisted,
      'numberPeopleGoing': instance.numberPeopleGoing,
      'maxPeople': instance.maxPeople,
      'registeredProfilePics': instance.registeredProfilePics,
    };
