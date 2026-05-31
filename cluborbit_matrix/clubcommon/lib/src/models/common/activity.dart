import 'package:json_annotation/json_annotation.dart';

/// This allows the `User` class to access private members in
/// the generated file. The value for this is *.g.dart, where
/// the star denotes the source file name.
part 'activity.g.dart';

@JsonSerializable()
class ActivityEntities {
  final List<ActivityEntity> activities;

  ActivityEntities({this.activities = const []});

  factory ActivityEntities.fromJson(Map<String, dynamic> json) =>
      _$ActivityEntitiesFromJson(json);

  Map<String, dynamic> toJson() => _$ActivityEntitiesToJson(this);
}

@JsonSerializable()
class ActivitySelect {
  final String name;
  //  final String? icon;

  ActivitySelect({
    required this.name, //, this.icon
  });

  factory ActivitySelect.fromJson(Map<String, dynamic> json) =>
      _$ActivitySelectFromJson(json);

  Map<String, dynamic> toJson() => _$ActivitySelectToJson(this);
}

@JsonSerializable()
class ActivityEntity {
  final String name;
  final String? icon;

  ActivityEntity({required this.name, this.icon});

  factory ActivityEntity.fromJson(Map<String, dynamic> json) =>
      _$ActivityEntityFromJson(json);

  Map<String, dynamic> toJson() => _$ActivityEntityToJson(this);
}

@JsonSerializable()
class Activity {
  final String name;
  final String? icon;

  Activity({required this.name, this.icon});

  factory Activity.fromJson(Map<String, dynamic> json) =>
      _$ActivityFromJson(json);

  Map<String, dynamic> toJson() => _$ActivityToJson(this);
}
