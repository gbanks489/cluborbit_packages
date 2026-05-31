// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MembershipEntity _$MembershipEntityFromJson(Map<String, dynamic> json) =>
    MembershipEntity(
      uid: json['uid'] as String,
      profilePicUrl: json['profilePicUrl'] as String?,
      club: json['club'] == null
          ? null
          : ClubEntity.fromJson(json['club'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$MembershipEntityToJson(MembershipEntity instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'club': instance.club,
      'profilePicUrl': instance.profilePicUrl,
    };

RegistrationEntity _$RegistrationEntityFromJson(Map<String, dynamic> json) =>
    RegistrationEntity(
      uid: json['uid'] as String,
      status: json['status'] as String,
      timestamp: json['timestamp'] == null
          ? null
          : IsoDateTime.fromJson(json['timestamp'] as String),
      userEntity: UserEntity.fromJson(
        json['userEntity'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$RegistrationEntityToJson(RegistrationEntity instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'status': instance.status,
      'timestamp': instance.timestamp,
      'userEntity': instance.userEntity,
    };

UserEntity _$UserEntityFromJson(Map<String, dynamic> json) => UserEntity(
  uid: json['uid'] as String,
  email: json['email'] as String,
  displayName: json['displayName'] as String,
  profilePicUrl: json['profilePicUrl'] as String?,
  memberships: (json['memberships'] as List<dynamic>?)
      ?.map((e) => MembershipEntity.fromJson(e as Map<String, dynamic>))
      .toList(),
  administrations: (json['administrations'] as List<dynamic>?)
      ?.map((e) => EventAdministratorEntity.fromJson(e as Map<String, dynamic>))
      .toList(),
  registrations: (json['registrations'] as List<dynamic>?)
      ?.map((e) => RegistrationEntity.fromJson(e as Map<String, dynamic>))
      .toList(),
  activities: (json['activities'] as List<dynamic>?)
      ?.map((e) => ActivityEntity.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$UserEntityToJson(UserEntity instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'email': instance.email,
      'profilePicUrl': instance.profilePicUrl,
      'displayName': instance.displayName,
      'memberships': instance.memberships,
      'administrations': instance.administrations,
      'registrations': instance.registrations,
      'activities': instance.activities,
    };

UserClubSnippet _$UserClubSnippetFromJson(Map<String, dynamic> json) =>
    UserClubSnippet(
      uid: json['uid'] as String,
      name: json['name'] as String,
      formattedAddress: json['formattedAddress'] as String?,
      staticMapUrl: json['staticMapUrl'] as String?,
      profilePicUrl: json['profilePicUrl'] as String?,
    );

Map<String, dynamic> _$UserClubSnippetToJson(UserClubSnippet instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'name': instance.name,
      'formattedAddress': instance.formattedAddress,
      'staticMapUrl': instance.staticMapUrl,
      'profilePicUrl': instance.profilePicUrl,
    };

User _$UserFromJson(Map<String, dynamic> json) => User(
  email: json['email'] as String,
  uid: json['uid'] as String,
  dateOfBirth: json['dateOfBirth'] == null
      ? null
      : IsoDateTime.fromJson(json['dateOfBirth'] as String),
  displayName: json['displayName'] as String,
  gender: $enumDecodeNullable(_$GenderEnumMap, json['gender']),
  profilePic: json['profilePic'] == null
      ? null
      : ImageEntity.fromJson(json['profilePic'] as Map<String, dynamic>),
  coverPicUrl: json['coverPicUrl'] as String?,
  chatToken: json['chatToken'] as String?,
  chatUsername: json['chatUsername'] as String?,
  bio: json['bio'] as String?,
  firstName: json['firstName'] as String?,
  lastName: json['lastName'] as String?,
  activities: (json['activities'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  permissions: (json['permissions'] as List<dynamic>?)
      ?.map((e) => $enumDecode(_$UserViewPermissionEnumMap, e))
      .toSet(),
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'email': instance.email,
  'uid': instance.uid,
  'gender': _$GenderEnumMap[instance.gender],
  'displayName': instance.displayName,
  'dateOfBirth': instance.dateOfBirth,
  'profilePic': instance.profilePic,
  'coverPicUrl': instance.coverPicUrl,
  'bio': instance.bio,
  'firstName': instance.firstName,
  'lastName': instance.lastName,
  'chatToken': instance.chatToken,
  'chatUsername': instance.chatUsername,
  'activities': instance.activities,
  'permissions': instance.permissions
      ?.map((e) => _$UserViewPermissionEnumMap[e]!)
      .toList(),
};

const _$GenderEnumMap = {
  Gender.male: 'male',
  Gender.female: 'female',
  Gender.other: 'other',
};

const _$UserViewPermissionEnumMap = {
  UserViewPermission.age: 'age',
  UserViewPermission.gender: 'gender',
  UserViewPermission.fullName: 'fullName',
};

UserDTO _$UserDTOFromJson(Map<String, dynamic> json) => UserDTO(
  user: User.fromJson(json['user'] as Map<String, dynamic>),
  userEntity: UserEntity.fromJson(json['userEntity'] as Map<String, dynamic>),
  chatUser: json['chatUser'] == null
      ? null
      : ChatUser.fromJson(json['chatUser'] as Map<String, dynamic>),
);

Map<String, dynamic> _$UserDTOToJson(UserDTO instance) => <String, dynamic>{
  'user': instance.user,
  'userEntity': instance.userEntity,
  'chatUser': instance.chatUser,
};
