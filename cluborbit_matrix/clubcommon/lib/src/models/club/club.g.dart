// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'club.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClubAnalytics _$ClubAnalyticsFromJson(Map<String, dynamic> json) =>
    ClubAnalytics(
      memberCount: (json['memberCount'] as num?)?.toInt(),
      faciiities: (json['faciiities'] as num?)?.toInt(),
      pastEventCount: (json['pastEventCount'] as num?)?.toInt(),
      futureEventCount: (json['futureEventCount'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ClubAnalyticsToJson(ClubAnalytics instance) =>
    <String, dynamic>{
      'memberCount': instance.memberCount,
      'faciiities': instance.faciiities,
      'pastEventCount': instance.pastEventCount,
      'futureEventCount': instance.futureEventCount,
    };

ClubUser _$ClubUserFromJson(Map<String, dynamic> json) => ClubUser(
  userUid: json['userUid'] as String,
  club: Club.fromJson(json['club'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ClubUserToJson(ClubUser instance) => <String, dynamic>{
  'userUid': instance.userUid,
  'club': instance.club,
};

UserClubRelationship _$UserClubRelationshipFromJson(
  Map<String, dynamic> json,
) => UserClubRelationship(
  userUid: json['userUid'] as String,
  clubUid: json['clubUid'] as String,
  type: $enumDecode(_$UserClubRelationshipTypeEnumMap, json['type']),
  relationshipUid: json['relationshipUid'] as String?,
);

Map<String, dynamic> _$UserClubRelationshipToJson(
  UserClubRelationship instance,
) => <String, dynamic>{
  'userUid': instance.userUid,
  'clubUid': instance.clubUid,
  'relationshipUid': instance.relationshipUid,
  'type': _$UserClubRelationshipTypeEnumMap[instance.type]!,
};

const _$UserClubRelationshipTypeEnumMap = {
  UserClubRelationshipType.belongs: 'belongs',
  UserClubRelationshipType.admin: 'admin',
};

AiClubResponse _$AiClubResponseFromJson(Map<String, dynamic> json) =>
    AiClubResponse(
      bio: json['bio'] as String?,
      activities: (json['activities'] as List<dynamic>?)
          ?.map((e) => Activity.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$AiClubResponseToJson(AiClubResponse instance) =>
    <String, dynamic>{'bio': instance.bio, 'activities': instance.activities};

Club _$ClubFromJson(Map<String, dynamic> json) => Club(
  uid: json['uid'] as String?,
  name: json['name'] as String,
  placeId: json['placeId'] as String,
  formattedAddress: json['formattedAddress'] as String,
  clubType: $enumDecode(_$ClubTypeEnumMap, json['clubType']),
  isPrivate: json['isPrivate'] as bool,
  masterClubUid: json['masterClubUid'] as String?,
  shortAddress: json['shortAddress'] as String?,
  location: json['location'] == null
      ? null
      : Location.fromJson(json['location'] as Map<String, dynamic>),
  roomAlias: json['roomAlias'] as String?,
  adminUid: json['adminUid'] as String?,
  phoneNumber: json['phoneNumber'] as String?,
  website: json['website'] as String?,
  profilePic: json['profilePic'] == null
      ? null
      : ImageEntity.fromJson(json['profilePic'] as Map<String, dynamic>),
  coverPicUrl: json['coverPicUrl'] as String?,
  about: json['about'] as String?,
  aiGenerated: json['aiGenerated'] as bool?,
  staticMapUrl: json['staticMapUrl'] as String?,
  activities: (json['activities'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  distance: (json['distance'] as num?)?.toDouble(),
  coverPicAttributions: (json['coverPicAttributions'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$ClubToJson(Club instance) => <String, dynamic>{
  'placeId': instance.placeId,
  'name': instance.name,
  'clubType': _$ClubTypeEnumMap[instance.clubType]!,
  'formattedAddress': instance.formattedAddress,
  'location': instance.location,
  'staticMapUrl': instance.staticMapUrl,
  'uid': instance.uid,
  'phoneNumber': instance.phoneNumber,
  'website': instance.website,
  'profilePic': instance.profilePic,
  'coverPicUrl': instance.coverPicUrl,
  'coverPicAttributions': instance.coverPicAttributions,
  'about': instance.about,
  'aiGenerated': instance.aiGenerated,
  'shortAddress': instance.shortAddress,
  'adminUid': instance.adminUid,
  'masterClubUid': instance.masterClubUid,
  'isPrivate': instance.isPrivate,
  'roomAlias': instance.roomAlias,
  'activities': instance.activities,
};

const _$ClubTypeEnumMap = {ClubType.club: 'club', ClubType.group: 'group'};
