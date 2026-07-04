import 'package:flutter/foundation.dart';

class IsoDateTime {
  final DateTime dateTime;

  IsoDateTime(this.dateTime);

  // Factory method to create an IsoDateTime from an ISO 8601 string
  factory IsoDateTime.fromIsoString(String isoString) {
    final parsedDateTime = DateTime.parse(isoString);
    return IsoDateTime(parsedDateTime);
  }

  // Serialize the DateTime to an ISO 8601 string
  String toIsoString() {
    if (kDebugMode) {
      print(dateTime.toUtc().toIso8601String());
    }
    return dateTime.toUtc().toIso8601String();
  }

  String timeAgo() {
    final difference = DateTime.now().difference(dateTime);

    if (difference.inDays >= 365) {
      final years = (difference.inDays / 365).floor();
      return '${years}y';
    } else if (difference.inDays >= 30) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo';
    } else if (difference.inDays >= 7) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'just now';
    }
  }

  // Add any other methods or properties you need

  // Include this line to generate the necessary serialization code
  factory IsoDateTime.fromJson(String json) {
    // Parse the ISO8601 string to a DateTime object
    DateTime parsedDateTime = DateTime.parse(json);
    // Convert from UTC to local time
    DateTime localDateTime = parsedDateTime.toLocal();
    return IsoDateTime(localDateTime);
  }

  // Modify this method to return a string
  String toJson() => toIsoString();

  /*
  // Include this line to generate the necessary serialization code
  factory IsoDateTime.fromJson(Map<String, dynamic> json) => _$IsoDateTimeFromJson(json);
  Map<String, dynamic> toJson() => _$IsoDateTimeToJson(this);
  */
}
