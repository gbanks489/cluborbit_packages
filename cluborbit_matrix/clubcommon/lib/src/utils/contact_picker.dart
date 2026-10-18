import 'dart:io';

import 'package:flutter/services.dart';

/// Someone picked from the phone's contacts: their name, numbers and emails - all the app gets.
class PickedContact {
  const PickedContact({required this.name, this.phones = const [], this.emails = const []});

  final String name;
  final List<String> phones;
  final List<String> emails;

  static PickedContact? fromMap(Object? raw) {
    if (raw is! Map) return null;
    List<String> list(Object? v) => [
      for (final e in (v as List?) ?? const [])
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
    final phones = list(raw['phones']);
    final emails = list(raw['emails']);
    final name = (raw['name'] as String?)?.trim() ?? '';
    if (name.isEmpty && phones.isEmpty && emails.isEmpty) return null;
    return PickedContact(
      name: name.isNotEmpty ? name : (phones.isNotEmpty ? phones.first : emails.first),
      phones: phones,
      emails: emails,
    );
  }
}

/// What to pick on Android, where the system picker hands back one item per pick.
enum ContactPickKind { phone, email }

/// The phone's own contact picker (the app's "cluborbit/contact_picker" channel - MainActivity /
/// AppDelegate): no contacts permission, and only the picked contact is seen.
///
/// iOS returns each picked contact whole (name, numbers, emails), several at once. Android returns
/// one number or one email per pick ([kind]), with the contact's name.
class ContactPicker {
  ContactPicker._();

  static const _channel = MethodChannel('cluborbit/contact_picker');

  /// Whether one pick returns the whole contact (iOS) - else a number or an email (Android).
  static bool get picksWholeContact => Platform.isIOS;

  /// The picked contacts - empty when cancelled.
  static Future<List<PickedContact>> pick({ContactPickKind kind = ContactPickKind.phone}) async {
    final result = await _channel.invokeMethod<Object?>('pick', {'kind': kind.name});
    final raw = result is List ? result : [result];
    return [
      for (final r in raw)
        if (PickedContact.fromMap(r) case final contact?) contact,
    ];
  }
}
