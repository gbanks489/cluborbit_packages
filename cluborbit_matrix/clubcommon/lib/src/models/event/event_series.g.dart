// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_series.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EventSeriesSummaryDTO _$EventSeriesSummaryDTOFromJson(
  Map<String, dynamic> json,
) => EventSeriesSummaryDTO(
  eventSeriesUid: json['eventSeriesUid'] as String,
  eventSeriesPicUrl: json['eventSeriesPicUrl'] as String?,
  eventSeriesPicScrollUrl: json['eventSeriesPicScrollUrl'] as String?,
  eventTitle: json['eventTitle'] as String?,
  clubPicUrl: json['clubPicUrl'] as String?,
  clubAddress: json['clubAddress'] as String?,
  recurring: json['recurring'] as bool,
  startDateTime: IsoDateTime.fromJson(json['startDateTime'] as String),
  endDateTime: IsoDateTime.fromJson(json['endDateTime'] as String),
  registrationCount: (json['registrationCount'] as num).toInt(),
  maxPeople: (json['maxPeople'] as num).toInt(),
  userRole: json['userRole'] as String?,
  activities: (json['activities'] as List<dynamic>?)
      ?.map((e) => ActivityEntity.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$EventSeriesSummaryDTOToJson(
  EventSeriesSummaryDTO instance,
) => <String, dynamic>{
  'eventSeriesUid': instance.eventSeriesUid,
  'eventSeriesPicUrl': instance.eventSeriesPicUrl,
  'eventSeriesPicScrollUrl': instance.eventSeriesPicScrollUrl,
  'eventTitle': instance.eventTitle,
  'clubPicUrl': instance.clubPicUrl,
  'clubAddress': instance.clubAddress,
  'recurring': instance.recurring,
  'registrationCount': instance.registrationCount,
  'maxPeople': instance.maxPeople,
  'userRole': instance.userRole,
  'startDateTime': instance.startDateTime,
  'endDateTime': instance.endDateTime,
  'activities': instance.activities,
};

EventSeriesEntity _$EventSeriesEntityFromJson(Map<String, dynamic> json) =>
    EventSeriesEntity(
        uid: json['uid'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        eventPicUrl: json['eventPicUrl'] as String?,
        eventPicScrollUrl: json['eventPicScrollUrl'] as String?,
        maxPeople: (json['maxPeople'] as num).toInt(),
        registrationCount: (json['registrationCount'] as num).toInt(),
        countViews: (json['countViews'] as num?)?.toInt(),
        countComments: (json['countComments'] as num?)?.toInt(),
        countLikes: (json['countLikes'] as num?)?.toInt(),
        timestamp: json['timestamp'] == null
            ? null
            : IsoDateTime.fromJson(json['timestamp'] as String),
        registrations: (json['registrations'] as List<dynamic>?)
            ?.map((e) => RegistrationEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
        memberships: (json['memberships'] as List<dynamic>?)
            ?.map((e) => MembershipEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
        administrator: json['administrator'] == null
            ? null
            : EventAdministratorEntity.fromJson(
                json['administrator'] as Map<String, dynamic>,
              ),
        eventDates: (json['eventDates'] as List<dynamic>?)
            ?.map((e) => EventDateEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
        club: json['club'] == null
            ? null
            : ClubEntity.fromJson(json['club'] as Map<String, dynamic>),
        posts: (json['posts'] as List<dynamic>?)
            ?.map((e) => PostEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
        activities: (json['activities'] as List<dynamic>?)
            ?.map((e) => ActivityEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
        roomAlias: json['roomAlias'] as String?,
      )
      ..eventPicFullUrl = json['eventPicFullUrl'] as String?
      ..likes = (json['likes'] as List<dynamic>?)
          ?.map((e) => UserEntity.fromJson(e as Map<String, dynamic>))
          .toList();

Map<String, dynamic> _$EventSeriesEntityToJson(EventSeriesEntity instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'title': instance.title,
      'description': instance.description,
      'eventPicUrl': instance.eventPicUrl,
      'eventPicScrollUrl': instance.eventPicScrollUrl,
      'eventPicFullUrl': instance.eventPicFullUrl,
      'registrationCount': instance.registrationCount,
      'maxPeople': instance.maxPeople,
      'countViews': instance.countViews,
      'countComments': instance.countComments,
      'countLikes': instance.countLikes,
      'timestamp': instance.timestamp,
      'roomAlias': instance.roomAlias,
      'registrations': instance.registrations,
      'memberships': instance.memberships,
      'administrator': instance.administrator,
      'eventDates': instance.eventDates,
      'posts': instance.posts,
      'likes': instance.likes,
      'club': instance.club,
      'activities': instance.activities,
    };

EventSeriesStatusRequest _$EventSeriesStatusRequestFromJson(
  Map<String, dynamic> json,
) => EventSeriesStatusRequest(
  eventSeriesUid: json['eventSeriesUid'] as String,
  eventStatus: $enumDecode(_$EventSeriesStatusTypeEnumMap, json['eventStatus']),
  postingsClosed: json['postingsClosed'] as bool?,
);

Map<String, dynamic> _$EventSeriesStatusRequestToJson(
  EventSeriesStatusRequest instance,
) => <String, dynamic>{
  'eventSeriesUid': instance.eventSeriesUid,
  'eventStatus': _$EventSeriesStatusTypeEnumMap[instance.eventStatus]!,
  'postingsClosed': instance.postingsClosed,
};

const _$EventSeriesStatusTypeEnumMap = {
  EventSeriesStatusType.activeOpenRegistration: 'activeOpenRegistration',
  EventSeriesStatusType.activeClosedRegistration: 'activeClosedRegistration',
  EventSeriesStatusType.cancelled: 'cancelled',
  EventSeriesStatusType.completed: 'completed',
};

EventSeries _$EventSeriesFromJson(Map<String, dynamic> json) => EventSeries(
  uid: json['uid'] as String?,
  clubId: json['clubId'] as String,
  title: json['title'] as String,
  description: json['description'] as String,
  eventSchedule: json['eventSchedule'] == null
      ? null
      : Schedule.fromJson(json['eventSchedule'] as Map<String, dynamic>),
  lastUpdatedUserUid: json['lastUpdatedUserUid'] as String,
  adminUid: json['adminUid'] as String,
  maxPeople: (json['maxPeople'] as num?)?.toInt(),
  eventPic: json['eventPic'] == null
      ? null
      : ImageEntity.fromJson(json['eventPic'] as Map<String, dynamic>),
  timestamp: json['timestamp'] == null
      ? null
      : IsoDateTime.fromJson(json['timestamp'] as String),
  activities: (json['activities'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  eventStatus: $enumDecodeNullable(
    _$EventSeriesStatusTypeEnumMap,
    json['eventStatus'],
  ),
)..postingsClosed = json['postingsClosed'] as bool?;

Map<String, dynamic> _$EventSeriesToJson(EventSeries instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'clubId': instance.clubId,
      'title': instance.title,
      'description': instance.description,
      'eventSchedule': instance.eventSchedule,
      'maxPeople': instance.maxPeople,
      'adminUid': instance.adminUid,
      'eventPic': instance.eventPic,
      'timestamp': instance.timestamp,
      'activities': instance.activities,
      'eventStatus': _$EventSeriesStatusTypeEnumMap[instance.eventStatus],
      'postingsClosed': instance.postingsClosed,
      'lastUpdatedUserUid': instance.lastUpdatedUserUid,
    };

EventSeriesDTO _$EventSeriesDTOFromJson(Map<String, dynamic> json) =>
    EventSeriesDTO(
      adminProfile: json['adminProfile'] == null
          ? null
          : UserProfileSnippet.fromJson(
              json['adminProfile'] as Map<String, dynamic>,
            ),
      eventSeries: EventSeries.fromJson(
        json['eventSeries'] as Map<String, dynamic>,
      ),
      eventDates: (json['eventDates'] as List<dynamic>)
          .map((e) => EventDate.fromJson(e as Map<String, dynamic>))
          .toList(),
      previousEventDates: (json['previousEventDates'] as List<dynamic>?)
          ?.map((e) => EventDateEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextEventDate: json['nextEventDate'] == null
          ? null
          : EventDateEntity.fromJson(
              json['nextEventDate'] as Map<String, dynamic>,
            ),
      futureEventDates: (json['futureEventDates'] as List<dynamic>?)
          ?.map((e) => EventDateEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      registrations: (json['registrations'] as List<dynamic>?)
          ?.map((e) => e as String?)
          .toList(),
      selectedEventDate: json['selectedEventDate'] == null
          ? null
          : EventDateEntity.fromJson(
              json['selectedEventDate'] as Map<String, dynamic>,
            ),
      eventUserStatus: $enumDecode(
        _$EventUserStatusEnumMap,
        json['eventUserStatus'],
      ),
      goingCount: (json['goingCount'] as num).toInt(),
      eventSeriesEntity: json['eventSeriesEntity'] == null
          ? null
          : EventSeriesEntity.fromJson(
              json['eventSeriesEntity'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$EventSeriesDTOToJson(EventSeriesDTO instance) =>
    <String, dynamic>{
      'eventSeries': instance.eventSeries,
      'eventSeriesEntity': instance.eventSeriesEntity,
      'adminProfile': instance.adminProfile,
      'eventDates': instance.eventDates,
      'previousEventDates': instance.previousEventDates,
      'nextEventDate': instance.nextEventDate,
      'futureEventDates': instance.futureEventDates,
      'selectedEventDate': instance.selectedEventDate,
      'registrations': instance.registrations,
      'eventUserStatus': _$EventUserStatusEnumMap[instance.eventUserStatus]!,
      'goingCount': instance.goingCount,
    };

const _$EventUserStatusEnumMap = {
  EventUserStatus.going: 'going',
  EventUserStatus.waitlisted: 'waitlisted',
  EventUserStatus.notGoing: 'notGoing',
  EventUserStatus.administers: 'administers',
};

EventSeriesUser _$EventSeriesUserFromJson(Map<String, dynamic> json) =>
    EventSeriesUser(
      userUid: json['userUid'] as String,
      eventSeries: EventSeries.fromJson(
        json['eventSeries'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$EventSeriesUserToJson(EventSeriesUser instance) =>
    <String, dynamic>{
      'userUid': instance.userUid,
      'eventSeries': instance.eventSeries,
    };
