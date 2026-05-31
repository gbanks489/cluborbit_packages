import 'package:clubcommon/src/models/club/club_details_dto.dart';
import 'package:clubcommon/src/models/common/activity.dart';
import 'package:clubcommon/src/models/common/chat_credentials.dart';
import 'package:clubcommon/src/models/common/image.dart';
import 'package:clubcommon/src/models/common/iso_datetime.dart';
import 'package:clubcommon/src/models/event/event.dart';
import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';
/*
@JsonSerializable()
class UserClubRelationship {
  String? relationshipUid;
  String userUid;
  String? userDisplayName;
  String? clubUid;
 // String? userProfilePicUrl;
  UserClubSnippet clubSnippet;

  UserClubRelationship({
    this.relationshipUid,
    required this.userUid,
    required this.userDisplayName,
    required this.clubUid,
    required this.clubSnippet,
   // required this.userProfilePicUrl
  }); 

  factory UserClubRelationship.fromJson(Map<String, dynamic> json) => _$UserClubRelationshipFromJson(json);
  
  Map<String, dynamic> toJson() => _$UserClubRelationshipToJson(this); 
} */

@JsonSerializable()
class MembershipEntity {
  String uid;
  ClubEntity? club;
  String? profilePicUrl;

  MembershipEntity({
    required this.uid,
    required this.profilePicUrl,
    required this.club,
  });

  factory MembershipEntity.fromJson(Map<String, dynamic> json) =>
      _$MembershipEntityFromJson(json);

  Map<String, dynamic> toJson() => _$MembershipEntityToJson(this);
}

@JsonSerializable()
class RegistrationEntity {
  String uid;
  String status;
  IsoDateTime? timestamp;
  UserEntity userEntity;

  RegistrationEntity({
    required this.uid,
    required this.status,
    this.timestamp,
    required this.userEntity,
  });

  factory RegistrationEntity.fromJson(Map<String, dynamic> json) =>
      _$RegistrationEntityFromJson(json);

  Map<String, dynamic> toJson() => _$RegistrationEntityToJson(this);
}

@JsonSerializable()
class UserEntity {
  String uid;
  String email;
  String? profilePicUrl;
  String displayName;

  List<MembershipEntity>? memberships;

  List<EventAdministratorEntity>? administrations;

  List<RegistrationEntity>? registrations;

  List<ActivityEntity>? activities;

  UserEntity({
    required this.uid,
    required this.email,
    required this.displayName,
    this.profilePicUrl,
    this.memberships,
    this.administrations,
    this.registrations,
    this.activities,
  });

  factory UserEntity.fromJson(Map<String, dynamic> json) =>
      _$UserEntityFromJson(json);

  Map<String, dynamic> toJson() => _$UserEntityToJson(this);
}

@JsonSerializable()
class UserClubSnippet {
  final String uid;
  final String name;
  final String? formattedAddress;
  final String? staticMapUrl;
  final String? profilePicUrl;

  UserClubSnippet({
    required this.uid,
    required this.name,
    required this.formattedAddress,
    required this.staticMapUrl,
    this.profilePicUrl,
  });

  factory UserClubSnippet.fromJson(Map<String, dynamic> json) =>
      _$UserClubSnippetFromJson(json);

  Map<String, dynamic> toJson() => _$UserClubSnippetToJson(this);
}

enum Gender { male, female, other }

enum UserViewPermission { age, gender, fullName }

@JsonSerializable()
class User {
  final String email;
  final String uid;
  Gender? gender;
  String displayName;
  IsoDateTime? dateOfBirth;
  ImageEntity? profilePic;
  String? coverPicUrl;
  String? bio;
  String? firstName;
  String? lastName;
  String? chatToken;
  String? chatUsername;
  List<String>? activities;
  Set<UserViewPermission>? permissions;

  User({
    required this.email,
    required this.uid,
    this.dateOfBirth,
    required this.displayName,
    this.gender,
    this.profilePic,
    this.coverPicUrl,
    this.chatToken,
    this.chatUsername,
    this.bio,
    this.firstName,
    this.lastName,
    this.activities,
    this.permissions,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  Map<String, dynamic> toJson() => _$UserToJson(this);
}

@JsonSerializable()
class UserDTO {
  User user;
  UserEntity userEntity;
  ChatUser? chatUser;

  UserDTO({required this.user, required this.userEntity, this.chatUser});

  factory UserDTO.fromJson(Map<String, dynamic> json) =>
      _$UserDTOFromJson(json);

  Map<String, dynamic> toJson() => _$UserDTOToJson(this);
}
