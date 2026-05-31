import 'dart:core';

import 'package:clubcommon/clubcommon.dart';
import 'package:clubcommon/src/models/common/activity.dart';
import 'package:clubcommon/src/models/common/image.dart';
import 'package:clubcommon/src/models/event/event_snippet.dart';
import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

part 'event_series.g.dart';

enum EventSeriesRole { hasRegistered, administers }

enum EventSeriesQueryDirection { before, after }

@JsonSerializable()
class EventSeriesSummaryDTO {
  String eventSeriesUid;
  String? eventSeriesPicUrl;
  String? eventSeriesPicScrollUrl;
  String? eventTitle;
  String? clubPicUrl;
  String? clubAddress;
  bool recurring;
  int registrationCount;
  int maxPeople;
  String? userRole;
  IsoDateTime startDateTime;
  IsoDateTime endDateTime;
  List<ActivityEntity>? activities;

  EventSeriesSummaryDTO({
    required this.eventSeriesUid,
    this.eventSeriesPicUrl,
    this.eventSeriesPicScrollUrl,
    this.eventTitle,
    this.clubPicUrl,
    this.clubAddress,
    required this.recurring,
    required this.startDateTime,
    required this.endDateTime,
    required this.registrationCount,
    required this.maxPeople,
    this.userRole,
    this.activities,
  });

  factory EventSeriesSummaryDTO.fromJson(Map<String, dynamic> json) =>
      _$EventSeriesSummaryDTOFromJson(json);

  Map<String, dynamic> toJson() => _$EventSeriesSummaryDTOToJson(this);
}

@JsonSerializable()
class EventSeriesEntity {
  String uid;
  String title;
  String? description;
  String? eventPicUrl;
  String? eventPicScrollUrl;
  String? eventPicFullUrl;
  int registrationCount;
  int maxPeople;
  int? countViews;
  int? countComments;
  int? countLikes;
  IsoDateTime? timestamp;
  String? roomAlias;

  List<RegistrationEntity>? registrations;

  List<MembershipEntity>? memberships;

  EventAdministratorEntity? administrator;

  List<EventDateEntity>? eventDates;

  List<PostEntity>? posts;

  List<UserEntity>? likes;

  ClubEntity? club;

  List<ActivityEntity>? activities;

  EventSeriesEntity({
    required this.uid,
    required this.title,
    this.description,
    required this.eventPicUrl,
    this.eventPicScrollUrl,
    required this.maxPeople,
    required this.registrationCount,
    this.countViews,
    this.countComments,
    this.countLikes,
    this.timestamp,
    this.registrations,
    this.memberships,
    this.administrator,
    this.eventDates,
    this.club,
    this.posts,
    this.activities,
    this.roomAlias,
  });

  static String buildDateTimeText(List<EventDateEntity> eventDates) {
    String dateBetween = "";
    if (eventDates.isNotEmpty) {
      dateBetween = EventSeries.buildDateTimeText(
        eventDates[0].startDateTime,
        eventDates[eventDates.length - 1].endDateTime,
      );

      // if (eventDates.length > 1) {
      //   dateBetween = EventSeries.buildDateTimeText(
      //     eventDates[0].startDateTime,
      //     eventDates[eventDates.length - 1].endDateTime,
      //   );
      // } else {
      //   dateBetween =
      //       DateFormat(
      //         "EEE, MMM d, h:mm a - ",
      //       ).format(eventDates[0].startDateTime.dateTime) +
      //       DateFormat(
      //         'EEE, MMM d, h:mm a',
      //       ).format(eventDates[0].endDateTime.dateTime);
      // }
    }

    return dateBetween;
  }

  factory EventSeriesEntity.fromJson(Map<String, dynamic> json) =>
      _$EventSeriesEntityFromJson(json);

  Map<String, dynamic> toJson() => _$EventSeriesEntityToJson(this);
}

enum EventSeriesStatusType {
  activeOpenRegistration,
  activeClosedRegistration,
  cancelled,
  completed,
}

@JsonSerializable()
class EventSeriesStatusRequest {
  final String eventSeriesUid;
  final EventSeriesStatusType eventStatus;
  final bool? postingsClosed;

  const EventSeriesStatusRequest({
    required this.eventSeriesUid,
    required this.eventStatus,
    this.postingsClosed,
  });

  factory EventSeriesStatusRequest.fromJson(Map<String, dynamic> json) =>
      _$EventSeriesStatusRequestFromJson(json);

  Map<String, dynamic> toJson() => _$EventSeriesStatusRequestToJson(this);
}

@JsonSerializable()
class EventSeries {
  String? uid;
  String clubId;
  String title;
  String description;
  Schedule? eventSchedule;
  int? maxPeople;
  String adminUid;
  ImageEntity? eventPic;
  IsoDateTime? timestamp;
  List<String>? activities;
  EventSeriesStatusType? eventStatus;
  bool? postingsClosed;

  //List<ClubActivity> activities;

  // @JsonKey(disallowNullValue: true)
  // DateTime? nextEventDate;

  //DateTime creationTime;
  //  DateTime lastUpdatedTime;
  // UserProfileSnippet? adminProfile;
  String lastUpdatedUserUid;
  //String? adminEventSnippetUid;

  EventSeries({
    this.uid,
    required this.clubId,
    required this.title,
    required this.description,
    required this.eventSchedule,
    required this.lastUpdatedUserUid,
    required this.adminUid,
    this.maxPeople,
    this.eventPic,
    this.timestamp,
    this.activities,
    this.eventStatus,
  });

  static String buildDateTimeText(IsoDateTime startDate, IsoDateTime endDate) {
    String eventTime = "";
    DateTime sd = startDate.dateTime;
    DateTime ed = endDate.dateTime;

    if (sd.day == ed.day) {
      eventTime =
          "${DateFormat("EEE, MMM d, h:mm a - ").format(sd)}"
          "${DateFormat('h:mm a').format(ed)}";
    } else {
      //if (sd.day < ed.day) {
      eventTime =
          "${DateFormat("EEE, MMM d, h:mm a - ").format(sd)}"
          "${DateFormat('EEE, MMM d, h:mm a').format(ed)}";
    }

    return eventTime;
  }

  String getPath() {
    return path;
  }

  factory EventSeries.fromJson(Map<String, dynamic> json) =>
      _$EventSeriesFromJson(json);

  Map<String, dynamic> toJson() => _$EventSeriesToJson(this);

  static String get path => "eventSeries";
}

@JsonSerializable()
class EventSeriesDTO {
  EventSeries eventSeries;
  EventSeriesEntity? eventSeriesEntity;
  UserProfileSnippet? adminProfile;
  List<EventDate> eventDates;
  List<EventDateEntity>? previousEventDates;
  EventDateEntity? nextEventDate;
  List<EventDateEntity>? futureEventDates;
  EventDateEntity? selectedEventDate;
  List<String?>? registrations;
  EventUserStatus eventUserStatus;
  int goingCount;

  EventSeriesDTO({
    this.adminProfile,
    required this.eventSeries,
    required this.eventDates,
    this.previousEventDates,
    this.nextEventDate,
    this.futureEventDates,
    this.registrations,
    this.selectedEventDate,
    required this.eventUserStatus,
    required this.goingCount,
    required this.eventSeriesEntity,
  });

  factory EventSeriesDTO.fromJson(Map<String, dynamic> json) =>
      _$EventSeriesDTOFromJson(json);

  Map<String, dynamic> toJson() => _$EventSeriesDTOToJson(this);
}

@JsonSerializable()
class EventSeriesUser {
  String userUid;
  EventSeries eventSeries;

  EventSeriesUser({required this.userUid, required this.eventSeries});

  String getPath() {
    return path;
  }

  factory EventSeriesUser.fromJson(Map<String, dynamic> json) =>
      _$EventSeriesUserFromJson(json);

  Map<String, dynamic> toJson() => _$EventSeriesUserToJson(this);

  static String get path => "eventSeriesUser";
}
