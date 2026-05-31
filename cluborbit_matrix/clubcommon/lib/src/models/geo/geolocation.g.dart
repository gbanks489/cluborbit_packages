// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'geolocation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GeolocationError _$GeolocationErrorFromJson(Map<String, dynamic> json) =>
    GeolocationError(
      domain: json['domain'] as String,
      reason: json['reason'] as String,
      message: json['message'] as String,
    );

Map<String, dynamic> _$GeolocationErrorToJson(GeolocationError instance) =>
    <String, dynamic>{
      'domain': instance.domain,
      'reason': instance.reason,
      'message': instance.message,
    };

GeolocationErrorResponse _$GeolocationErrorResponseFromJson(
  Map<String, dynamic> json,
) => GeolocationErrorResponse(
  errors:
      (json['errors'] as List<dynamic>?)
          ?.map((e) => GeolocationError.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  code: (json['code'] as num).toInt(),
  message: json['message'] as String,
);

Map<String, dynamic> _$GeolocationErrorResponseToJson(
  GeolocationErrorResponse instance,
) => <String, dynamic>{
  'errors': instance.errors,
  'code': instance.code,
  'message': instance.message,
};

GeolocationResponse _$GeolocationResponseFromJson(Map<String, dynamic> json) =>
    GeolocationResponse(
      location: json['location'] == null
          ? null
          : Location.fromJson(json['location'] as Map<String, dynamic>),
      accuracy: json['accuracy'] as num?,
      error: json['error'] == null
          ? null
          : GeolocationErrorResponse.fromJson(
              json['error'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$GeolocationResponseToJson(
  GeolocationResponse instance,
) => <String, dynamic>{
  'location': instance.location,
  'accuracy': instance.accuracy,
  'error': instance.error,
};

CellTower _$CellTowerFromJson(Map<String, dynamic> json) => CellTower(
  cellId: json['cellId'] as num,
  locationAreaCode: json['locationAreaCode'] as num,
  mobileCountryCode: json['mobileCountryCode'] as num,
  mobileNetworkCode: json['mobileNetworkCode'] as num,
  timingAdvance: json['timingAdvance'] as num?,
  age: json['age'] as num?,
  signalStrength: json['signalStrength'] as num?,
);

Map<String, dynamic> _$CellTowerToJson(CellTower instance) => <String, dynamic>{
  'age': instance.age,
  'signalStrength': instance.signalStrength,
  'cellId': instance.cellId,
  'locationAreaCode': instance.locationAreaCode,
  'mobileCountryCode': instance.mobileCountryCode,
  'mobileNetworkCode': instance.mobileNetworkCode,
  'timingAdvance': instance.timingAdvance,
};

WifiAccessPoint _$WifiAccessPointFromJson(Map<String, dynamic> json) =>
    WifiAccessPoint(
      age: json['age'] as num?,
      signalStrength: json['signalStrength'] as num?,
      macAddress: json['macAddress'] as String?,
      channel: json['channel'],
      signalToNoiseRatio: json['signalToNoiseRatio'] as num?,
    );

Map<String, dynamic> _$WifiAccessPointToJson(WifiAccessPoint instance) =>
    <String, dynamic>{
      'age': instance.age,
      'signalStrength': instance.signalStrength,
      'macAddress': instance.macAddress,
      'channel': instance.channel,
      'signalToNoiseRatio': instance.signalToNoiseRatio,
    };
