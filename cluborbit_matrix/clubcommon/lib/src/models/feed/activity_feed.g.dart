// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_feed.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ActivityFeedItems _$ActivityFeedItemsFromJson(Map<String, dynamic> json) =>
    ActivityFeedItems(
      activityFeedItems:
          (json['activityFeedItems'] as List<dynamic>?)
              ?.map((e) => ActivityFeedItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ActivityFeedItemsToJson(ActivityFeedItems instance) =>
    <String, dynamic>{'activityFeedItems': instance.activityFeedItems};

DistanceDTO _$DistanceDTOFromJson(Map<String, dynamic> json) => DistanceDTO(
  fromEntity: json['fromEntity'] as String?,
  lat: (json['lat'] as num?)?.toDouble(),
  lng: (json['lng'] as num?)?.toDouble(),
  distance: (json['distance'] as num?)?.toDouble(),
);

Map<String, dynamic> _$DistanceDTOToJson(DistanceDTO instance) =>
    <String, dynamic>{
      'fromEntity': instance.fromEntity,
      'lat': instance.lat,
      'lng': instance.lng,
      'distance': instance.distance,
    };

ActivityFeedItem _$ActivityFeedItemFromJson(Map<String, dynamic> json) =>
    ActivityFeedItem(
        eventSeriesEntity: json['eventSeriesEntity'] == null
            ? null
            : EventSeriesEntity.fromJson(
                json['eventSeriesEntity'] as Map<String, dynamic>,
              ),
        postEntity: json['postEntity'] == null
            ? null
            : PostEntity.fromJson(json['postEntity'] as Map<String, dynamic>),
        timestamp: json['timestamp'] == null
            ? null
            : IsoDateTime.fromJson(json['timestamp'] as String),
        type:
            $enumDecodeNullable(_$ActivityFeedItemTypeEnumMap, json['type']) ??
            ActivityFeedItemType.eventSeriesEntity,
      )
      ..distance = json['distance'] == null
          ? null
          : DistanceDTO.fromJson(json['distance'] as Map<String, dynamic>);

Map<String, dynamic> _$ActivityFeedItemToJson(ActivityFeedItem instance) =>
    <String, dynamic>{
      'type': _$ActivityFeedItemTypeEnumMap[instance.type]!,
      'eventSeriesEntity': instance.eventSeriesEntity,
      'postEntity': instance.postEntity,
      'timestamp': instance.timestamp,
      'distance': instance.distance,
    };

const _$ActivityFeedItemTypeEnumMap = {
  ActivityFeedItemType.eventSeriesEntity: 'eventSeriesEntity',
  ActivityFeedItemType.postEntity: 'postEntity',
};
