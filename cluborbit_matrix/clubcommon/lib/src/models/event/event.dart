import 'package:clubcommon/clubcommon.dart';
import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:timezone/timezone.dart' as tz;

part 'event.g.dart';

enum Weekday {
  @JsonValue('MONDAY')
  monday,
  @JsonValue('TUESDAY')
  tuesday,
  @JsonValue('WEDNESDAY')
  wednesday,
  @JsonValue('THURSDAY')
  thursday,
  @JsonValue('FRIDAY')
  friday,
  @JsonValue('SATURDAY')
  saturday,
  @JsonValue('SUNDAY')
  sunday,
}

enum RecurringFrequency {
  @JsonValue('DAYS')
  days,
  @JsonValue('WEEKS')
  weeks,
  @JsonValue('MONTHS')
  months,
}

enum EventStatus { canceled, active, completed }

@JsonSerializable()
class EventDate {
  String? eventSeriesUid;
  String? uid;
  IsoDateTime startDateTime;
  IsoDateTime endDateTime;
  // String? eventPicUrl;
  //  bool? isRecurring;
  // String? title;
  EventStatus status;

  EventDate({
    this.uid,
    this.eventSeriesUid,
    // this.eventPicUrl,
    //  this.isRecurring,
    this.status = EventStatus.active,
    required this.startDateTime,
    required this.endDateTime,
  });

  EventDate.copy(String? eventSeriesId, EventDateEntity event)
    : uid = event.uid,
      eventSeriesUid = eventSeriesId,
      status = event.status,
      startDateTime = event.startDateTime,
      endDateTime = event.endDateTime;

  String toDisplayString() {
    String displayString = "";
    DateTime sd = startDateTime.dateTime;
    DateTime ed = endDateTime.dateTime;

    if (sd.day == ed.day) {
      displayString =
          "${DateFormat("EEEE, MMM d\nh:mm a - ").format(sd)}"
          "${DateFormat('h:mm a').format(ed)}";
    } else if (sd.day < ed.day) {
      displayString =
          "${DateFormat("EEEE, MMM d, h:mm a -\n").format(sd)}"
          "${DateFormat('EEEE, MMM d, h:mm a').format(ed)}";
    }

    return displayString;
  }

  factory EventDate.fromJson(Map<String, dynamic> json) =>
      _$EventDateFromJson(json);

  Map<String, dynamic> toJson() => _$EventDateToJson(this);

  static String get path => "eventDate";
}

@JsonSerializable()
class EventDateEntity {
  String? uid;
  IsoDateTime startDateTime;
  IsoDateTime endDateTime;
  EventStatus status;
  List<PostEntity>? posts;
  EventSeriesEntity? eventSeries;

  EventDateEntity({
    this.uid,
    // this.eventPicUrl,  ntity
    //  this.isRecurring,
    this.posts,
    this.status = EventStatus.active,
    required this.startDateTime,
    required this.endDateTime,
    this.eventSeries,
  });

  String toDisplayString() {
    String displayString = "";
    DateTime sd = startDateTime.dateTime;
    DateTime ed = endDateTime.dateTime;

    if (sd.day == ed.day) {
      displayString =
          "${DateFormat("EEEE, MMM d\nh:mm a - ").format(sd)} ${DateFormat('h:mm a').format(ed)}";
    } else {
      displayString =
          "${DateFormat("EEEE, MMM d, h:mm a -\n").format(sd)}"
          "${DateFormat('EEEE, MMM d, h:mm a').format(ed)}";
    }

    return displayString;
  }

  String toDisplayStringShort() {
    String displayString = "";
    DateTime sd = startDateTime.dateTime;

    displayString = DateFormat("EEE, MMM d h:mm a").format(sd);

    return displayString;
  }

  factory EventDateEntity.fromJson(Map<String, dynamic> json) =>
      _$EventDateEntityFromJson(json);

  Map<String, dynamic> toJson() => _$EventDateEntityToJson(this);
}

@JsonSerializable()
class EventInstance {
  String eventDateUid;
  IsoDateTime startDateTime;
  IsoDateTime endDateTime;

  EventInstance({
    required this.eventDateUid,
    required this.startDateTime,
    required this.endDateTime,
  });

  factory EventInstance.fromJson(Map<String, dynamic> json) =>
      _$EventInstanceFromJson(json);

  Map<String, dynamic> toJson() => _$EventInstanceToJson(this);
}

@JsonSerializable()
class EventAdministratorEntity {
  String uid;
  UserEntity userEntity;

  EventAdministratorEntity({required this.uid, required this.userEntity});

  factory EventAdministratorEntity.fromJson(Map<String, dynamic> json) =>
      _$EventAdministratorEntityFromJson(json);

  Map<String, dynamic> toJson() => _$EventAdministratorEntityToJson(this);
}

@JsonSerializable()
class Schedule {
  bool isRecurring;
  RecurringFrequency? frequencyType;
  List<Weekday>? eventWeekdays;
  int? occurFrequency;
  int? numberOfOccurrences;
  IsoDateTime startDate;
  IsoDateTime endDate;
  Duration? recurringDuration;
  String? timezone;

  @JsonKey(includeFromJson: false, includeToJson: false)
  String? _displayString;

  Schedule({
    required this.isRecurring,
    required this.startDate,
    required this.endDate,
    this.numberOfOccurrences,
    this.occurFrequency,
    this.eventWeekdays,
    this.frequencyType,
    this.recurringDuration,
    this.timezone,
  }) {
    eventWeekdays!.sort(mySortComparison);
  }

  String get displayString => _displayString!;
  void setDisplayString() {
    _displayString = toDisplayString();
  }

  static final Map<int, String> weekdayName = {
    1: "Monday",
    2: "Tuesday",
    3: "Wednesday",
    4: "Thursday",
    5: "Friday",
    6: "Saturday",
    7: "Sunday",
  };

  factory Schedule.fromJson(Map<String, dynamic> json) =>
      _$ScheduleFromJson(json);

  Map<String, dynamic> toJson() {
    return _$ScheduleToJson(this);
  }

  //  Schedule copyWith() => Schedule(
  //        startDate: startDate,
  //        endDate: endDate ?? endDate,
  //      );
  static int mySortComparison(Weekday a, Weekday b) {
    if (a.index < b.index) {
      return -1;
    } else if (a.index > b.index) {
      return 1;
    } else {
      return 0;
    }
  }

  static List<EventDate> generateDatesFromSchedule(Schedule schedule) {
    if (schedule.isRecurring) {
      return generateEventDates(
        schedule.isRecurring,
        schedule.frequencyType,
        schedule.eventWeekdays!,
        schedule.occurFrequency!,
        schedule.numberOfOccurrences!,
        schedule.startDate,
        schedule.endDate,
        schedule.timezone,
      );
    } else {
      List<EventDate> eventDates = [];

      EventDate eventDate = EventDate(
        startDateTime: schedule.startDate,
        endDateTime: schedule.endDate,
      );

      eventDates.add(eventDate);
      return eventDates;
    }
  }

  static List<EventDate> generateEventDates(
    bool isRecurring,
    RecurringFrequency? frequencyType,
    List<Weekday> eventWeekdays,
    int occurFrequency,
    int numberOfOccurrences,
    IsoDateTime startDateStartTime,
    IsoDateTime startDateEndTime,
    String? timezone,
  ) {
    List<EventDate> eventDates = [];

    eventWeekdays.sort(mySortComparison);
    //   DateTime endDateStartTime = startDateStartTime.dateTime;
    //   DateTime endDateEndTime = startDateEndTime.dateTime;
    //   DateTime sDateStartTime =  startDateStartTime.dateTime;

    // Get the location for your timezone, for example, 'America/New_York'
    //final location = tz.getLocation('America/New_York');
    final location = tz.getLocation(timezone!);
    tz.TZDateTime endDateStartTime = tz.TZDateTime.from(
      startDateStartTime.dateTime,
      location,
    );
    tz.TZDateTime endDateEndTime = tz.TZDateTime.from(
      startDateEndTime.dateTime,
      location,
    );
    tz.TZDateTime sDateStartTime = tz.TZDateTime.from(
      startDateStartTime.dateTime,
      location,
    );

    // // Create the initial date-time in your timezone
    // tz.TZDateTime endDateStartTime =
    // tz.TZDateTime.parse(location, "2025-03-10T18:00:00");
    // int addDays = 7;

    // Add the duration without shifting the hour
    //tz.TZDateTime adjustedDateTime = endDateStartTime.add(Duration(days: addDays));

    // Print the adjusted date-time
    //print('Adjusted DateTime: ${adjustedDateTime.toString()}');

    if (frequencyType == RecurringFrequency.weeks) {
      int addDays = 0;
      int numTimes = numberOfOccurrences * eventWeekdays.length;

      int startingIdx = startDateStartTime.dateTime.weekday - 1;
      int idx = 0;

      // TODO add error for days of week
      if (eventWeekdays.length == 0) {
        return [];
      }

      while (idx < eventWeekdays.length &&
          eventWeekdays[idx].index < startingIdx) {
        idx++;
      }

      // if day of week > last element
      if (idx == eventWeekdays.length) {
        idx = 0;
        addDays =
            7 -
            (sDateStartTime.weekday - 1 - eventWeekdays[0].index) +
            7 * (occurFrequency - 1);
      } else {
        addDays = eventWeekdays[idx].index - (sDateStartTime.weekday - 1);
      }

      endDateStartTime = endDateStartTime.add(Duration(days: addDays));
      endDateEndTime = endDateEndTime.add(Duration(days: addDays));

      endDateStartTime = tz.TZDateTime(
        location,
        endDateStartTime.year,
        endDateStartTime.month,
        endDateStartTime.day,
        startDateStartTime.dateTime.hour,
        startDateStartTime.dateTime.minute,
      );

      endDateEndTime = tz.TZDateTime(
        location,
        endDateEndTime.year,
        endDateEndTime.month,
        endDateEndTime.day,
        startDateEndTime.dateTime.hour,
        startDateEndTime.dateTime.minute,
      );

      eventDates.add(
        EventDate(
          startDateTime: IsoDateTime(endDateStartTime),
          endDateTime: IsoDateTime(endDateEndTime),
        ),
      );

      numTimes--;

      int i = idx;
      while (numTimes > 0) {
        addDays = 0;
        for (; i < eventWeekdays.length; i++) {
          if (i == eventWeekdays.length - 1) {
            addDays =
                7 -
                (eventWeekdays[i].index - eventWeekdays[0].index) +
                7 * (occurFrequency - 1);
          } else {
            addDays = eventWeekdays[i + 1].index - eventWeekdays[i].index;
          }

          endDateStartTime = endDateStartTime.add(Duration(days: addDays));
          endDateEndTime = endDateEndTime.add(Duration(days: addDays));
          // Correct for the time shift due to DST
          endDateStartTime = tz.TZDateTime(
            location,
            endDateStartTime.year,
            endDateStartTime.month,
            endDateStartTime.day,
            startDateStartTime.dateTime.hour,
            startDateStartTime.dateTime.minute,
          );

          endDateEndTime = tz.TZDateTime(
            location,
            endDateEndTime.year,
            endDateEndTime.month,
            endDateEndTime.day,
            startDateEndTime.dateTime.hour,
            startDateEndTime.dateTime.minute,
          );

          eventDates.add(
            EventDate(
              startDateTime: IsoDateTime(endDateStartTime),
              endDateTime: IsoDateTime(endDateEndTime),
            ),
          );

          numTimes--;

          if (numTimes == 0) {
            break;
          }
        }

        i = 0;
      }
    }

    return eventDates;
  }

  String toDisplayString() {
    String displayString = "";

    if (isRecurring && numberOfOccurrences != null && eventWeekdays != null
    //    && numberOfOccurrences! > 1
    ) {
      displayString = "Occurs every ";

      if (occurFrequency != null && occurFrequency! > 1) {
        displayString += "${int.parse(occurFrequency.toString())} weeks\n";
      } else {
        displayString += "week\n";
      }

      for (var i = 0; i < eventWeekdays!.length; i++) {
        if (i == eventWeekdays!.length - 1 && eventWeekdays!.length > 1) {
          displayString += " and ";
        } else if (i > 0) {
          displayString += ", ";
        }

        displayString += weekdayName[eventWeekdays![i].index + 1]!;
      }

      List<EventDate> eventDates = generateEventDates(
        isRecurring,
        frequencyType,
        eventWeekdays!,
        occurFrequency!,
        numberOfOccurrences!,
        startDate,
        endDate,
        timezone,
      );

      DateTime beginStartDate = eventDates[0].startDateTime.dateTime;
      DateTime endStartDate =
          eventDates[eventDates.length - 1].startDateTime.dateTime;
      DateTime endEndDate = endStartDate.add(
        recurringDuration ?? const Duration(hours: 1),
      );

      /*  DateTime newEndDate =  DateTime(eventDates[eventDates.length - 1].endDateTime.dateTime.year, 
                                                  eventDates[eventDates.length - 1].endDateTime.dateTime.month, 
                                                  eventDates[eventDates.length - 1].endDateTime.dateTime.day,
                                                  endDate.dateTime.hour, 
                                                  endDate.dateTime.minute,
                                                  endDate.dateTime.second); */

      displayString += DateFormat("\nMMM d - ").format(beginStartDate);
      displayString += DateFormat("MMM d").format(endStartDate);

      displayString += "\n${DateFormat("h:mm a - ").format(endStartDate)}";
      displayString += DateFormat("h:mm a").format(endEndDate);
    } else {
      if (startDate.dateTime.day == endDate.dateTime.day) {
        displayString =
            "${DateFormat("EEEE, MMM d, h:mm a - ").format(startDate.dateTime)}"
            "${DateFormat('h:mm a').format(endDate.dateTime)}";
      } else if (startDate.dateTime.day < endDate.dateTime.day) {
        displayString =
            "${DateFormat("EEEE, MMM d, h:mm a - ").format(startDate.dateTime)}"
            "${DateFormat('EEEE, MMM d, h:mm a').format(endDate.dateTime)}";
      }
    }

    if (timezone != null && timezone!.isNotEmpty) {
      displayString += "\n$timezone";
    }

    return displayString;
  }
}

@JsonSerializable()
class Event {
  String? uid;
  IsoDateTime startDateTime;
  IsoDateTime endDateTime;
  String? eventSeriesUid;
  //String? adminEventSnippetUid;

  Event({
    required this.uid,
    required this.startDateTime,
    required this.endDateTime,
    this.eventSeriesUid,
  });

  String getPath() {
    return path;
  }

  factory Event.fromJson(Map<String, dynamic> json) => _$EventFromJson(json);

  Map<String, dynamic> toJson() => _$EventToJson(this);

  static String get path => "events";
}

@JsonSerializable()
class EventSeriesSnippet {
  String uid;
  String title;
  String? eventPicUrl;
  //String? adminEventSnippetUid;

  EventSeriesSnippet({
    required this.uid,
    required this.title,
    this.eventPicUrl,
  });

  String getPath() {
    return path;
  }

  factory EventSeriesSnippet.fromJson(Map<String, dynamic> json) =>
      _$EventSeriesSnippetFromJson(json);

  Map<String, dynamic> toJson() => _$EventSeriesSnippetToJson(this);

  static String get path => "eventSeriesSnippet";
}

@JsonSerializable()
class EventClubSnippet {
  String uid;
  String name;
  String? profilePicUrl;

  //String? adminEventSnippetUid;

  EventClubSnippet({required this.uid, required this.name});

  String getPath() {
    return path;
  }

  factory EventClubSnippet.fromJson(Map<String, dynamic> json) =>
      _$EventClubSnippetFromJson(json);

  Map<String, dynamic> toJson() => _$EventClubSnippetToJson(this);

  static String get path => "eventClubSnippet";
}

@JsonSerializable()
class EventSummary {
  Event eventDate;
  EventSeriesSnippet eventSeries;
  EventClubSnippet club;

  EventSummary({
    required this.eventDate,
    required this.eventSeries,
    required this.club,
  });

  factory EventSummary.fromJson(Map<String, dynamic> json) =>
      _$EventSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$EventSummaryToJson(this);
}

@JsonSerializable()
class EventSummaries {
  List<EventSummary> eventSummaries;

  EventSummaries({this.eventSummaries = const []});

  factory EventSummaries.fromJson(Map<String, dynamic> json) =>
      _$EventSummariesFromJson(json);
  Map<String, dynamic> toJson() => _$EventSummariesToJson(this);
}
