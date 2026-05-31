// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'feed_home.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FeedHome _$FeedHomeFromJson(Map<String, dynamic> json) =>
    FeedHome(
        activityFeedItems:
            (json['activityFeedItems'] as List<dynamic>?)
                ?.map(
                  (e) => ActivityFeedItem.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            const [],
        clubs: (json['clubs'] as List<dynamic>?)
            ?.map((e) => ClubEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
      )
      ..activities = (json['activities'] as List<dynamic>?)
          ?.map((e) => ActivityEntity.fromJson(e as Map<String, dynamic>))
          .toList();

Map<String, dynamic> _$FeedHomeToJson(FeedHome instance) => <String, dynamic>{
  'activityFeedItems': instance.activityFeedItems,
  'clubs': instance.clubs,
  'activities': instance.activities,
};
