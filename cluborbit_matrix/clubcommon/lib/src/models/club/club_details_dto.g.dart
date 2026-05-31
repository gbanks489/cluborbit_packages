// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'club_details_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClubEntity _$ClubEntityFromJson(Map<String, dynamic> json) => ClubEntity(
  uid: json['uid'] as String,
  name: json['name'] as String,
  placeId: json['placeId'] as String,
  memberCount: (json['memberCount'] as num).toInt(),
  viewCount: (json['viewCount'] as num).toInt(),
  profilePicUrl: json['profilePicUrl'] as String?,
  formattedAddress: json['formattedAddress'] as String,
  shortAddress: json['shortAddress'] as String?,
  activities: (json['activities'] as List<dynamic>?)
      ?.map((e) => ActivityEntity.fromJson(e as Map<String, dynamic>))
      .toList(),
  about: json['about'] as String?,
  aiGenerated: json['aiGenerated'] as bool?,
  adminProfile: json['adminProfile'] == null
      ? null
      : UserEntity.fromJson(json['adminProfile'] as Map<String, dynamic>),
  groups: (json['groups'] as List<dynamic>?)
      ?.map((e) => ClubEntity.fromJson(e as Map<String, dynamic>))
      .toList(),
  hostClub: json['hostClub'] == null
      ? null
      : ClubEntity.fromJson(json['hostClub'] as Map<String, dynamic>),
  type: $enumDecodeNullable(_$ClubTypeEnumMap, json['type']),
  lat: (json['lat'] as num?)?.toDouble(),
  lng: (json['lng'] as num?)?.toDouble(),
  distance: (json['distance'] as num?)?.toDouble(),
  memberships: (json['memberships'] as List<dynamic>?)
      ?.map((e) => MembershipEntity.fromJson(e as Map<String, dynamic>))
      .toList(),
)..profilePicUrlScroll = json['profilePicUrlScroll'] as String?;

Map<String, dynamic> _$ClubEntityToJson(ClubEntity instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'name': instance.name,
      'formattedAddress': instance.formattedAddress,
      'shortAddress': instance.shortAddress,
      'profilePicUrl': instance.profilePicUrl,
      'profilePicUrlScroll': instance.profilePicUrlScroll,
      'placeId': instance.placeId,
      'memberCount': instance.memberCount,
      'viewCount': instance.viewCount,
      'activities': instance.activities,
      'groups': instance.groups,
      'hostClub': instance.hostClub,
      'about': instance.about,
      'aiGenerated': instance.aiGenerated,
      'type': _$ClubTypeEnumMap[instance.type],
      'lat': instance.lat,
      'lng': instance.lng,
      'distance': instance.distance,
      'adminProfile': instance.adminProfile,
      'memberships': instance.memberships,
    };

const _$ClubTypeEnumMap = {ClubType.club: 'club', ClubType.group: 'group'};

ClubSnippetDTO _$ClubSnippetDTOFromJson(Map<String, dynamic> json) =>
    ClubSnippetDTO(
      name: json['name'] as String,
      formattedAddress: json['formattedAddress'] as String,
      profilePicUrl: json['profilePicUrl'] as String?,
      uid: json['uid'] as String,
      memberCount: (json['memberCount'] as num).toInt(),
      activities: (json['activities'] as List<dynamic>?)
          ?.map((e) => ActivityEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      userRole: json['userRole'] as String,
    );

Map<String, dynamic> _$ClubSnippetDTOToJson(ClubSnippetDTO instance) =>
    <String, dynamic>{
      'name': instance.name,
      'formattedAddress': instance.formattedAddress,
      'profilePicUrl': instance.profilePicUrl,
      'uid': instance.uid,
      'memberCount': instance.memberCount,
      'userRole': instance.userRole,
      'activities': instance.activities,
    };

ClubDetailsDTO _$ClubDetailsDTOFromJson(Map<String, dynamic> json) =>
    ClubDetailsDTO(
        club: json['club'] == null
            ? null
            : Club.fromJson(json['club'] as Map<String, dynamic>),
        analytics: json['analytics'] == null
            ? null
            : ClubAnalytics.fromJson(json['analytics'] as Map<String, dynamic>),
        memberships: (json['memberships'] as List<dynamic>?)
            ?.map((e) => MembershipEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
        eventSeries: (json['eventSeries'] as List<dynamic>?)
            ?.map(
              (e) => EventSeriesSummaryDTO.fromJson(e as Map<String, dynamic>),
            )
            .toList(),
        activities: (json['activities'] as List<dynamic>?)
            ?.map((e) => ActivityEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
        groups: (json['groups'] as List<dynamic>?)
            ?.map((e) => ClubEntity.fromJson(e as Map<String, dynamic>))
            .toList(),
      )
      ..clubEntity = json['clubEntity'] == null
          ? null
          : ClubEntity.fromJson(json['clubEntity'] as Map<String, dynamic>)
      ..hostClub = json['hostClub'] == null
          ? null
          : Club.fromJson(json['hostClub'] as Map<String, dynamic>)
      ..adminProfile = json['adminProfile'] == null
          ? null
          : UserProfileSnippet.fromJson(
              json['adminProfile'] as Map<String, dynamic>,
            );

Map<String, dynamic> _$ClubDetailsDTOToJson(ClubDetailsDTO instance) =>
    <String, dynamic>{
      'club': instance.club,
      'clubEntity': instance.clubEntity,
      'hostClub': instance.hostClub,
      'adminProfile': instance.adminProfile,
      'analytics': instance.analytics,
      'memberships': instance.memberships,
      'eventSeries': instance.eventSeries,
      'groups': instance.groups,
      'activities': instance.activities,
    };
