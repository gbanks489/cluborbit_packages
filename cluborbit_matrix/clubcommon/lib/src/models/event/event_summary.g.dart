// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EventSummaryItems _$EventSummaryItemsFromJson(Map<String, dynamic> json) =>
    EventSummaryItems(
      eventSummaryItems:
          (json['eventSummaryItems'] as List<dynamic>?)
              ?.map((e) => EventSummaryItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$EventSummaryItemsToJson(EventSummaryItems instance) =>
    <String, dynamic>{'eventSummaryItems': instance.eventSummaryItems};

EventSummaryItem _$EventSummaryItemFromJson(Map<String, dynamic> json) =>
    EventSummaryItem(
      clubName: json['clubName'] as String?,
      eventSeriesUid: json['eventSeriesUid'] as String,
      eventDateUid: json['eventDateUid'] as String?,
      eventSeriesTitle: json['eventSeriesTitle'] as String,
      eventSeriesPicUrl: json['eventSeriesPicUrl'] as String?,
      startDateTime: IsoDateTime.fromJson(json['startDateTime'] as String),
      endDateTime: IsoDateTime.fromJson(json['endDateTime'] as String),
      role: json['role'] as String?,
      userProfilePicUrl: json['userProfilePicUrl'] as String?,
      userDisplayName: json['userDisplayName'] as String?,
      numEvents: (json['numEvents'] as num).toInt(),
      description: json['description'] as String?,
    )..clubPicUrl = json['clubPicUrl'] as String?;

Map<String, dynamic> _$EventSummaryItemToJson(EventSummaryItem instance) =>
    <String, dynamic>{
      'eventDateUid': instance.eventDateUid,
      'eventSeriesUid': instance.eventSeriesUid,
      'clubName': instance.clubName,
      'clubPicUrl': instance.clubPicUrl,
      'eventSeriesPicUrl': instance.eventSeriesPicUrl,
      'eventSeriesTitle': instance.eventSeriesTitle,
      'startDateTime': instance.startDateTime,
      'endDateTime': instance.endDateTime,
      'role': instance.role,
      'userProfilePicUrl': instance.userProfilePicUrl,
      'userDisplayName': instance.userDisplayName,
      'numEvents': instance.numEvents,
      'description': instance.description,
    };
