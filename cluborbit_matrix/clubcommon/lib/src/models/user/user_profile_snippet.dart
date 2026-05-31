import 'package:json_annotation/json_annotation.dart';

part 'user_profile_snippet.g.dart';

@JsonSerializable()
class UserProfileSnippet {
  String? profilePicUrl;
  String? displayName;
  String uid;

  UserProfileSnippet({
    required this.uid,  
    required this.profilePicUrl,
    required this.displayName
  });

  factory UserProfileSnippet.fromJson(Map<String, dynamic> json) => _$UserProfileSnippetFromJson(json);
  
  Map<String, dynamic> toJson() => _$UserProfileSnippetToJson(this); 

} 