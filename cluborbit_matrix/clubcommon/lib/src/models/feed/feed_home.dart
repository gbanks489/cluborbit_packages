import 'package:clubcommon/src/models/club/club_details_dto.dart';
import 'package:clubcommon/src/models/common/activity.dart';
import 'package:clubcommon/src/models/feed/activity_feed.dart';
import 'package:json_annotation/json_annotation.dart';

part 'feed_home.g.dart';

@JsonSerializable()
class FeedHome {
  final List<ActivityFeedItem> activityFeedItems;
  List<ClubEntity>? clubs;
  List<ActivityEntity>? activities;

  FeedHome({this.activityFeedItems = const [], this.clubs});

  factory FeedHome.fromJson(Map<String, dynamic> json) =>
      _$FeedHomeFromJson(json);
  Map<String, dynamic> toJson() => _$FeedHomeToJson(this);
}
