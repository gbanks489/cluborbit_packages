// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'directions.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DirectionsResponse _$DirectionsResponseFromJson(Map<String, dynamic> json) =>
    DirectionsResponse(
      status: json['status'] as String,
      errorMessage: json['errorMessage'] as String?,
      geocodedWaypoints:
          (json['geocodedWaypoints'] as List<dynamic>?)
              ?.map((e) => GeocodedWaypoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      routes:
          (json['routes'] as List<dynamic>?)
              ?.map((e) => Route.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$DirectionsResponseToJson(DirectionsResponse instance) =>
    <String, dynamic>{
      'status': instance.status,
      'errorMessage': instance.errorMessage,
      'geocodedWaypoints': instance.geocodedWaypoints,
      'routes': instance.routes,
    };

Waypoint _$WaypointFromJson(Map<String, dynamic> json) =>
    Waypoint(value: json['value'] as String);

Map<String, dynamic> _$WaypointToJson(Waypoint instance) => <String, dynamic>{
  'value': instance.value,
};

GeocodedWaypoint _$GeocodedWaypointFromJson(Map<String, dynamic> json) =>
    GeocodedWaypoint(
      geocoderStatus: json['geocoderStatus'] as String,
      placeId: json['placeId'] as String,
      types:
          (json['types'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          [],
      partialMatch: json['partialMatch'] as bool? ?? false,
    );

Map<String, dynamic> _$GeocodedWaypointToJson(GeocodedWaypoint instance) =>
    <String, dynamic>{
      'geocoderStatus': instance.geocoderStatus,
      'placeId': instance.placeId,
      'types': instance.types,
      'partialMatch': instance.partialMatch,
    };

Route _$RouteFromJson(Map<String, dynamic> json) => Route(
  summary: json['summary'] as String,
  legs:
      (json['legs'] as List<dynamic>?)
          ?.map((e) => Leg.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  copyrights: json['copyrights'] as String,
  overviewPolyline: Polyline.fromJson(
    json['overviewPolyline'] as Map<String, dynamic>,
  ),
  warnings: json['warnings'] as List<dynamic>,
  waypointOrder:
      (json['waypointOrder'] as List<dynamic>?)
          ?.map((e) => e as num)
          .toList() ??
      [],
  bounds: Bounds.fromJson(json['bounds'] as Map<String, dynamic>),
  fare: json['fare'] == null
      ? null
      : Fare.fromJson(json['fare'] as Map<String, dynamic>),
);

Map<String, dynamic> _$RouteToJson(Route instance) => <String, dynamic>{
  'summary': instance.summary,
  'legs': instance.legs,
  'copyrights': instance.copyrights,
  'overviewPolyline': instance.overviewPolyline,
  'warnings': instance.warnings,
  'waypointOrder': instance.waypointOrder,
  'bounds': instance.bounds,
  'fare': instance.fare,
};

Leg _$LegFromJson(Map<String, dynamic> json) => Leg(
  steps:
      (json['steps'] as List<dynamic>?)
          ?.map((e) => Step.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  startAddress: json['startAddress'] as String,
  endAddress: json['endAddress'] as String,
  durationInTraffic: json['durationInTraffic'] == null
      ? null
      : Value.fromJson(json['durationInTraffic'] as Map<String, dynamic>),
  arrivalTime: json['arrivalTime'] == null
      ? null
      : Time.fromJson(json['arrivalTime'] as Map<String, dynamic>),
  departureTime: json['departureTime'] == null
      ? null
      : Time.fromJson(json['departureTime'] as Map<String, dynamic>),
  startLocation: Location.fromJson(
    json['startLocation'] as Map<String, dynamic>,
  ),
  endLocation: Location.fromJson(json['endLocation'] as Map<String, dynamic>),
  duration: Value.fromJson(json['duration'] as Map<String, dynamic>),
  distance: Value.fromJson(json['distance'] as Map<String, dynamic>),
);

Map<String, dynamic> _$LegToJson(Leg instance) => <String, dynamic>{
  'startLocation': instance.startLocation,
  'endLocation': instance.endLocation,
  'duration': instance.duration,
  'distance': instance.distance,
  'steps': instance.steps,
  'startAddress': instance.startAddress,
  'endAddress': instance.endAddress,
  'durationInTraffic': instance.durationInTraffic,
  'arrivalTime': instance.arrivalTime,
  'departureTime': instance.departureTime,
};

Step _$StepFromJson(Map<String, dynamic> json) => Step(
  travelMode: $enumDecode(_$TravelModeEnumMap, json['travelMode']),
  htmlInstructions: json['htmlInstructions'] as String,
  polyline: Polyline.fromJson(json['polyline'] as Map<String, dynamic>),
  startLocation: Location.fromJson(
    json['startLocation'] as Map<String, dynamic>,
  ),
  endLocation: Location.fromJson(json['endLocation'] as Map<String, dynamic>),
  duration: Value.fromJson(json['duration'] as Map<String, dynamic>),
  distance: Value.fromJson(json['distance'] as Map<String, dynamic>),
  transitDetails: json['transitDetails'] == null
      ? null
      : TransitDetails.fromJson(json['transitDetails'] as Map<String, dynamic>),
  maneuver: json['maneuver'] as String?,
);

Map<String, dynamic> _$StepToJson(Step instance) => <String, dynamic>{
  'startLocation': instance.startLocation,
  'endLocation': instance.endLocation,
  'duration': instance.duration,
  'distance': instance.distance,
  'travelMode': _$TravelModeEnumMap[instance.travelMode]!,
  'htmlInstructions': instance.htmlInstructions,
  'maneuver': instance.maneuver,
  'polyline': instance.polyline,
  'transitDetails': instance.transitDetails,
};

const _$TravelModeEnumMap = {
  TravelMode.driving: 'DRIVING',
  TravelMode.walking: 'WALKING',
  TravelMode.bicycling: 'BICYCLING',
  TravelMode.transit: 'TRANSIT',
};

Polyline _$PolylineFromJson(Map<String, dynamic> json) =>
    Polyline(points: json['points'] as String);

Map<String, dynamic> _$PolylineToJson(Polyline instance) => <String, dynamic>{
  'points': instance.points,
};

Value _$ValueFromJson(Map<String, dynamic> json) =>
    Value(value: json['value'] as num, text: json['text'] as String);

Map<String, dynamic> _$ValueToJson(Value instance) => <String, dynamic>{
  'value': instance.value,
  'text': instance.text,
};

Fare _$FareFromJson(Map<String, dynamic> json) => Fare(
  currency: json['currency'] as String,
  value: json['value'] as num,
  text: json['text'] as String,
);

Map<String, dynamic> _$FareToJson(Fare instance) => <String, dynamic>{
  'value': instance.value,
  'text': instance.text,
  'currency': instance.currency,
};

Time _$TimeFromJson(Map<String, dynamic> json) => Time(
  timeZone: json['timeZone'] as String,
  value: json['value'] as num,
  text: json['text'] as String,
);

Map<String, dynamic> _$TimeToJson(Time instance) => <String, dynamic>{
  'value': instance.value,
  'text': instance.text,
  'timeZone': instance.timeZone,
};

TransitDetails _$TransitDetailsFromJson(
  Map<String, dynamic> json,
) => TransitDetails(
  arrivalStop: Stop.fromJson(json['arrivalStop'] as Map<String, dynamic>),
  departureStop: Stop.fromJson(json['departureStop'] as Map<String, dynamic>),
  arrivalTime: Time.fromJson(json['arrivalTime'] as Map<String, dynamic>),
  departureTime: Time.fromJson(json['departureTime'] as Map<String, dynamic>),
  headsign: json['headsign'] as String,
  headway: json['headway'] as num,
  numStops: json['numStops'] as num,
);

Map<String, dynamic> _$TransitDetailsToJson(TransitDetails instance) =>
    <String, dynamic>{
      'arrivalStop': instance.arrivalStop,
      'departureStop': instance.departureStop,
      'arrivalTime': instance.arrivalTime,
      'departureTime': instance.departureTime,
      'headsign': instance.headsign,
      'headway': instance.headway,
      'numStops': instance.numStops,
    };

Stop _$StopFromJson(Map<String, dynamic> json) => Stop(
  name: json['name'] as String,
  location: Location.fromJson(json['location'] as Map<String, dynamic>),
);

Map<String, dynamic> _$StopToJson(Stop instance) => <String, dynamic>{
  'name': instance.name,
  'location': instance.location,
};

Line _$LineFromJson(Map<String, dynamic> json) => Line(
  name: json['name'] as String,
  shortName: json['shortName'] as String,
  color: json['color'] as String,
  agencies: (json['agencies'] as List<dynamic>)
      .map((e) => TransitAgency.fromJson(e as Map<String, dynamic>))
      .toList(),
  url: json['url'] as String,
  icon: json['icon'] as String,
  textColor: json['textColor'] as String,
  vehicle: VehicleType.fromJson(json['vehicle'] as Map<String, dynamic>),
);

Map<String, dynamic> _$LineToJson(Line instance) => <String, dynamic>{
  'name': instance.name,
  'shortName': instance.shortName,
  'color': instance.color,
  'agencies': instance.agencies,
  'url': instance.url,
  'icon': instance.icon,
  'textColor': instance.textColor,
  'vehicle': instance.vehicle,
};

TransitAgency _$TransitAgencyFromJson(Map<String, dynamic> json) =>
    TransitAgency(
      name: json['name'] as String,
      url: json['url'] as String,
      phone: json['phone'] as String,
    );

Map<String, dynamic> _$TransitAgencyToJson(TransitAgency instance) =>
    <String, dynamic>{
      'name': instance.name,
      'url': instance.url,
      'phone': instance.phone,
    };

VehicleType _$VehicleTypeFromJson(Map<String, dynamic> json) => VehicleType(
  name: json['name'] as String,
  type: json['type'] as String,
  icon: json['icon'] as String,
  localIcon: json['localIcon'] as String,
);

Map<String, dynamic> _$VehicleTypeToJson(VehicleType instance) =>
    <String, dynamic>{
      'name': instance.name,
      'type': instance.type,
      'icon': instance.icon,
      'localIcon': instance.localIcon,
    };
