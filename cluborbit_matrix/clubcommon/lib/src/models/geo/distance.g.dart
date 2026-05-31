// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'distance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DistanceResponse _$DistanceResponseFromJson(Map<String, dynamic> json) =>
    DistanceResponse(
      status: json['status'] as String,
      errorMessage: json['errorMessage'] as String?,
      originAddresses:
          (json['originAddresses'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      destinationAddresses:
          (json['destinationAddresses'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      rows:
          (json['rows'] as List<dynamic>?)
              ?.map((e) => Row.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$DistanceResponseToJson(DistanceResponse instance) =>
    <String, dynamic>{
      'status': instance.status,
      'errorMessage': instance.errorMessage,
      'originAddresses': instance.originAddresses,
      'destinationAddresses': instance.destinationAddresses,
      'rows': instance.rows,
    };

Row _$RowFromJson(Map<String, dynamic> json) => Row(
  elements:
      (json['elements'] as List<dynamic>?)
          ?.map((e) => Element.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$RowToJson(Row instance) => <String, dynamic>{
  'elements': instance.elements,
};

Element _$ElementFromJson(Map<String, dynamic> json) => Element(
  distance: Value.fromJson(json['distance'] as Map<String, dynamic>),
  duration: Value.fromJson(json['duration'] as Map<String, dynamic>),
  elementStatus: json['elementStatus'] as String?,
);

Map<String, dynamic> _$ElementToJson(Element instance) => <String, dynamic>{
  'distance': instance.distance,
  'duration': instance.duration,
  'elementStatus': instance.elementStatus,
};

Value _$ValueFromJson(Map<String, dynamic> json) =>
    Value(value: json['value'] as num, text: json['text'] as String);

Map<String, dynamic> _$ValueToJson(Value instance) => <String, dynamic>{
  'value': instance.value,
  'text': instance.text,
};
