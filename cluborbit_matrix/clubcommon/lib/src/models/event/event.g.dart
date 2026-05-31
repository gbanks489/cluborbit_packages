// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EventDate _$EventDateFromJson(Map<String, dynamic> json) => EventDate(
  uid: json['uid'] as String?,
  eventSeriesUid: json['eventSeriesUid'] as String?,
  status:
      $enumDecodeNullable(_$EventStatusEnumMap, json['status']) ??
      EventStatus.active,
  startDateTime: IsoDateTime.fromJson(json['startDateTime'] as String),
  endDateTime: IsoDateTime.fromJson(json['endDateTime'] as String),
);

Map<String, dynamic> _$EventDateToJson(EventDate instance) => <String, dynamic>{
  'eventSeriesUid': instance.eventSeriesUid,
  'uid': instance.uid,
  'startDateTime': instance.startDateTime,
  'endDateTime': instance.endDateTime,
  'status': _$EventStatusEnumMap[instance.status]!,
};

const _$EventStatusEnumMap = {
  EventStatus.canceled: 'canceled',
  EventStatus.active: 'active',
  EventStatus.completed: 'completed',
};

EventDateEntity _$EventDateEntityFromJson(Map<String, dynamic> json) =>
    EventDateEntity(
      uid: json['uid'] as String?,
      posts: (json['posts'] as List<dynamic>?)
          ?.map((e) => PostEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      status:
          $enumDecodeNullable(_$EventStatusEnumMap, json['status']) ??
          EventStatus.active,
      startDateTime: IsoDateTime.fromJson(json['startDateTime'] as String),
      endDateTime: IsoDateTime.fromJson(json['endDateTime'] as String),
      eventSeries: json['eventSeries'] == null
          ? null
          : EventSeriesEntity.fromJson(
              json['eventSeries'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$EventDateEntityToJson(EventDateEntity instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'startDateTime': instance.startDateTime,
      'endDateTime': instance.endDateTime,
      'status': _$EventStatusEnumMap[instance.status]!,
      'posts': instance.posts,
      'eventSeries': instance.eventSeries,
    };

EventInstance _$EventInstanceFromJson(Map<String, dynamic> json) =>
    EventInstance(
      eventDateUid: json['eventDateUid'] as String,
      startDateTime: IsoDateTime.fromJson(json['startDateTime'] as String),
      endDateTime: IsoDateTime.fromJson(json['endDateTime'] as String),
    );

Map<String, dynamic> _$EventInstanceToJson(EventInstance instance) =>
    <String, dynamic>{
      'eventDateUid': instance.eventDateUid,
      'startDateTime': instance.startDateTime,
      'endDateTime': instance.endDateTime,
    };

EventAdministratorEntity _$EventAdministratorEntityFromJson(
  Map<String, dynamic> json,
) => EventAdministratorEntity(
  uid: json['uid'] as String,
  userEntity: UserEntity.fromJson(json['userEntity'] as Map<String, dynamic>),
);

Map<String, dynamic> _$EventAdministratorEntityToJson(
  EventAdministratorEntity instance,
) => <String, dynamic>{'uid': instance.uid, 'userEntity': instance.userEntity};

Schedule _$ScheduleFromJson(Map<String, dynamic> json) => Schedule(
  isRecurring: json['isRecurring'] as bool,
  startDate: IsoDateTime.fromJson(json['startDate'] as String),
  endDate: IsoDateTime.fromJson(json['endDate'] as String),
  numberOfOccurrences: (json['numberOfOccurrences'] as num?)?.toInt(),
  occurFrequency: (json['occurFrequency'] as num?)?.toInt(),
  eventWeekdays: (json['eventWeekdays'] as List<dynamic>?)
      ?.map((e) => $enumDecode(_$WeekdayEnumMap, e))
      .toList(),
  frequencyType: $enumDecodeNullable(
    _$RecurringFrequencyEnumMap,
    json['frequencyType'],
  ),
  recurringDuration: json['recurringDuration'] == null
      ? null
      : Duration(microseconds: (json['recurringDuration'] as num).toInt()),
  timezone: json['timezone'] as String?,
);

Map<String, dynamic> _$ScheduleToJson(Schedule instance) => <String, dynamic>{
  'isRecurring': instance.isRecurring,
  'frequencyType': _$RecurringFrequencyEnumMap[instance.frequencyType],
  'eventWeekdays': instance.eventWeekdays
      ?.map((e) => _$WeekdayEnumMap[e]!)
      .toList(),
  'occurFrequency': instance.occurFrequency,
  'numberOfOccurrences': instance.numberOfOccurrences,
  'startDate': instance.startDate,
  'endDate': instance.endDate,
  'recurringDuration': instance.recurringDuration?.inMicroseconds,
  'timezone': instance.timezone,
};

const _$WeekdayEnumMap = {
  Weekday.monday: 'MONDAY',
  Weekday.tuesday: 'TUESDAY',
  Weekday.wednesday: 'WEDNESDAY',
  Weekday.thursday: 'THURSDAY',
  Weekday.friday: 'FRIDAY',
  Weekday.saturday: 'SATURDAY',
  Weekday.sunday: 'SUNDAY',
};

const _$RecurringFrequencyEnumMap = {
  RecurringFrequency.days: 'DAYS',
  RecurringFrequency.weeks: 'WEEKS',
  RecurringFrequency.months: 'MONTHS',
};

Event _$EventFromJson(Map<String, dynamic> json) => Event(
  uid: json['uid'] as String?,
  startDateTime: IsoDateTime.fromJson(json['startDateTime'] as String),
  endDateTime: IsoDateTime.fromJson(json['endDateTime'] as String),
  eventSeriesUid: json['eventSeriesUid'] as String?,
);

Map<String, dynamic> _$EventToJson(Event instance) => <String, dynamic>{
  'uid': instance.uid,
  'startDateTime': instance.startDateTime,
  'endDateTime': instance.endDateTime,
  'eventSeriesUid': instance.eventSeriesUid,
};

EventSeriesSnippet _$EventSeriesSnippetFromJson(Map<String, dynamic> json) =>
    EventSeriesSnippet(
      uid: json['uid'] as String,
      title: json['title'] as String,
      eventPicUrl: json['eventPicUrl'] as String?,
    );

Map<String, dynamic> _$EventSeriesSnippetToJson(EventSeriesSnippet instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'title': instance.title,
      'eventPicUrl': instance.eventPicUrl,
    };

EventClubSnippet _$EventClubSnippetFromJson(Map<String, dynamic> json) =>
    EventClubSnippet(uid: json['uid'] as String, name: json['name'] as String)
      ..profilePicUrl = json['profilePicUrl'] as String?;

Map<String, dynamic> _$EventClubSnippetToJson(EventClubSnippet instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'name': instance.name,
      'profilePicUrl': instance.profilePicUrl,
    };

EventSummary _$EventSummaryFromJson(Map<String, dynamic> json) => EventSummary(
  eventDate: Event.fromJson(json['eventDate'] as Map<String, dynamic>),
  eventSeries: EventSeriesSnippet.fromJson(
    json['eventSeries'] as Map<String, dynamic>,
  ),
  club: EventClubSnippet.fromJson(json['club'] as Map<String, dynamic>),
);

Map<String, dynamic> _$EventSummaryToJson(EventSummary instance) =>
    <String, dynamic>{
      'eventDate': instance.eventDate,
      'eventSeries': instance.eventSeries,
      'club': instance.club,
    };

EventSummaries _$EventSummariesFromJson(Map<String, dynamic> json) =>
    EventSummaries(
      eventSummaries:
          (json['eventSummaries'] as List<dynamic>?)
              ?.map((e) => EventSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$EventSummariesToJson(EventSummaries instance) =>
    <String, dynamic>{'eventSummaries': instance.eventSummaries};
