// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ActivityEntities _$ActivityEntitiesFromJson(Map<String, dynamic> json) =>
    ActivityEntities(
      activities:
          (json['activities'] as List<dynamic>?)
              ?.map((e) => ActivityEntity.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ActivityEntitiesToJson(ActivityEntities instance) =>
    <String, dynamic>{'activities': instance.activities};

ActivitySelect _$ActivitySelectFromJson(Map<String, dynamic> json) =>
    ActivitySelect(name: json['name'] as String);

Map<String, dynamic> _$ActivitySelectToJson(ActivitySelect instance) =>
    <String, dynamic>{'name': instance.name};

ActivityEntity _$ActivityEntityFromJson(Map<String, dynamic> json) =>
    ActivityEntity(name: json['name'] as String, icon: json['icon'] as String?);

Map<String, dynamic> _$ActivityEntityToJson(ActivityEntity instance) =>
    <String, dynamic>{'name': instance.name, 'icon': instance.icon};

Activity _$ActivityFromJson(Map<String, dynamic> json) =>
    Activity(name: json['name'] as String, icon: json['icon'] as String?);

Map<String, dynamic> _$ActivityToJson(Activity instance) => <String, dynamic>{
  'name': instance.name,
  'icon': instance.icon,
};
