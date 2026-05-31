import 'package:clubcommon/src/models/common/iso_datetime.dart';
import 'package:json_annotation/json_annotation.dart';

part 'event_summary.g.dart';

@JsonSerializable()
class EventSummaryItems {
  final List<EventSummaryItem> eventSummaryItems;

  EventSummaryItems({this.eventSummaryItems = const []});

  factory EventSummaryItems.fromJson(Map<String, dynamic> json) =>
      _$EventSummaryItemsFromJson(json);
  Map<String, dynamic> toJson() => _$EventSummaryItemsToJson(this);
}

@JsonSerializable()
class EventSummaryItem {
  String? eventDateUid;
  String eventSeriesUid;
  String? clubName;
  String? clubPicUrl;
  String? eventSeriesPicUrl;
  String eventSeriesTitle;
  IsoDateTime startDateTime;
  IsoDateTime endDateTime;
  String? role;
  String? userProfilePicUrl;
  String? userDisplayName;
  int numEvents = 1;
  String? description;

  EventSummaryItem({
    required this.clubName,
    required this.eventSeriesUid,
    required this.eventDateUid,
    required this.eventSeriesTitle,
    required this.eventSeriesPicUrl,
    required this.startDateTime,
    required this.endDateTime,
    required this.role,
    this.userProfilePicUrl,
    this.userDisplayName,
    required this.numEvents,
    this.description,
  });

  String getPath() {
    return path;
  }

  factory EventSummaryItem.fromJson(Map<String, dynamic> json) =>
      _$EventSummaryItemFromJson(json);

  Map<String, dynamic> toJson() => _$EventSummaryItemToJson(this);

  static String get path => "eventSummaryItem";
}
