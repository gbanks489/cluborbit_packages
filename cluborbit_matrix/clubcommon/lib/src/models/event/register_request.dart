import 'package:clubcommon/src/models/event/event_snippet.dart';
import 'package:json_annotation/json_annotation.dart';

part 'register_request.g.dart';

@JsonSerializable()
class RegisterRequest {
  String eventSeriesUid;
  String userUid;
  EventUserStatus eventUserStatus;

  RegisterRequest({
    required this.eventSeriesUid,
    required this.userUid,
    required this.eventUserStatus,
  });

  factory RegisterRequest.fromJson(Map<String, dynamic> json) =>
      _$RegisterRequestFromJson(json);

  Map<String, dynamic> toJson() => _$RegisterRequestToJson(this);
}

@JsonSerializable()
class RegisterResponse {
  EventUserStatus status;
  int numberPeopleWaitlisted;
  int numberPeopleGoing;
  int maxPeople;
  List<String?>? registeredProfilePics;

  RegisterResponse({
    required this.status,
    required this.numberPeopleWaitlisted,
    required this.numberPeopleGoing,
    required this.maxPeople,
    this.registeredProfilePics,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) =>
      _$RegisterResponseFromJson(json);

  Map<String, dynamic> toJson() => _$RegisterResponseToJson(this);
}
