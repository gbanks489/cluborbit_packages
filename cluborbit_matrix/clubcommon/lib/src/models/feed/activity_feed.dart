import 'package:clubcommon/src/models/common/iso_datetime.dart';
import 'package:clubcommon/src/models/event/event_series.dart';
import 'package:clubcommon/src/models/post/post.dart';
import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';
import 'dart:math';

part 'activity_feed.g.dart';

@JsonSerializable()
class ActivityFeedItems {
  final List<ActivityFeedItem> activityFeedItems;

  ActivityFeedItems({this.activityFeedItems = const []});

  factory ActivityFeedItems.fromJson(Map<String, dynamic> json) =>
      _$ActivityFeedItemsFromJson(json);
  Map<String, dynamic> toJson() => _$ActivityFeedItemsToJson(this);
}

enum ActivityFeedItemType { eventSeriesEntity, postEntity }

@JsonSerializable()
class DistanceDTO {
  final String? fromEntity;
  final double? lat;
  final double? lng;
  final double? distance;

  const DistanceDTO({
    required this.fromEntity,
    required this.lat,
    required this.lng,
    this.distance,
  });

  String? toDisplay() {
    if (distance != null) {
      double d = distance! / 1000;

      if (d < 1) {
        return "${NumberFormat('#,##0').format(d * 1000)} m";
      } else if (d < 10) {
        return "${NumberFormat('#,##0.0').format(d)} km";
      } else {
        return "${NumberFormat('#,##0').format(d)} km";
      }
    } else {
      return null;
    }
  }

  static double calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double R = 6371; // Earth radius in km

    final double latDistance = _toRadians(lat2 - lat1);
    final double lngDistance = _toRadians(lng2 - lng1);

    final double a =
        sin(latDistance / 2) * sin(latDistance / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(lngDistance / 2) *
            sin(lngDistance / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c * 1000; // meters
  }

  static double _toRadians(double degree) => degree * pi / 180;

  factory DistanceDTO.fromJson(Map<String, dynamic> json) =>
      _$DistanceDTOFromJson(json);

  Map<String, dynamic> toJson() => _$DistanceDTOToJson(this);
}

@JsonSerializable()
class ActivityFeedItem {
  ActivityFeedItemType type;
  EventSeriesEntity? eventSeriesEntity;
  PostEntity? postEntity;
  IsoDateTime? timestamp;
  DistanceDTO? distance;

  ActivityFeedItem({
    this.eventSeriesEntity,
    this.postEntity,
    this.timestamp,
    this.type = ActivityFeedItemType.eventSeriesEntity,
  });

  String getPath() {
    return path;
  }

  factory ActivityFeedItem.fromJson(Map<String, dynamic> json) =>
      _$ActivityFeedItemFromJson(json);

  Map<String, dynamic> toJson() => _$ActivityFeedItemToJson(this);

  static String get path => "activityFeedItem";
}

/*
@JsonSerializable()
class ActivityFeedItem {
  String eventDateUid;
  String eventSeriesUid;
  String clubName;
  String? eventPicUrl;
  String eventSeriesTitle;
  DateTime startDateTime;
  DateTime endDateTime;

  ActivityFeedItem({
    required this.clubName,
    required this.eventSeriesUid,
    required this.eventDateUid,
    required this.eventSeriesTitle,
    required this.eventPicUrl,
    required this.startDateTime,
    required this.endDateTime
  });

  String getPath() { return path; }

  factory ActivityFeedItem.fromJson(Map<String, dynamic> json) => _$ActivityFeedItemFromJson(json);
  
  Map<String, dynamic> toJson() => _$ActivityFeedItemToJson(this); 

  static String get path => "activityFeedItem";


}
*/
