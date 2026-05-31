
import 'package:json_annotation/json_annotation.dart';

part 'chat_credentials.g.dart';

@JsonSerializable(explicitToJson: true)
class ChatUser {
  final String userName;
  final String password;

  ChatUser({required this.userName, required this.password });

  factory ChatUser.fromJson(Map<String, dynamic> json) => _$ChatUserFromJson(json);
  Map<String, dynamic> toJson() => _$ChatUserToJson(this);
}
