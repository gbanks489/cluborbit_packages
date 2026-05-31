import 'package:json_annotation/json_annotation.dart';

part 'event_action.g.dart';
enum EventActionStatus {
  going,
  notGoing
}

@JsonSerializable()
class EventAction {
  String userUid;
  String eventUid;
  EventActionStatus eventActionStatus;
  DateTime updatedTime;

  EventAction({
    required this.userUid,
    required this.eventUid,
    required this.eventActionStatus,
    required this.updatedTime
  });

  factory EventAction.fromJson(Map<String, dynamic> json) => _$EventActionFromJson(json);
  
  Map<String, dynamic> toJson() => _$EventActionToJson(this);
}