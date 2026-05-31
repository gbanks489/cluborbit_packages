// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_snippet.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserProfileSnippet _$UserProfileSnippetFromJson(Map<String, dynamic> json) =>
    UserProfileSnippet(
      uid: json['uid'] as String,
      profilePicUrl: json['profilePicUrl'] as String?,
      displayName: json['displayName'] as String?,
    );

Map<String, dynamic> _$UserProfileSnippetToJson(UserProfileSnippet instance) =>
    <String, dynamic>{
      'profilePicUrl': instance.profilePicUrl,
      'displayName': instance.displayName,
      'uid': instance.uid,
    };
