import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../controllers/chat_controller.dart';

class IncomingCallSettingsStore {
  IncomingCallSettingsStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const String _autoOpenKey = 'incoming_call.auto_open_full_screen';
  static const String _ringtoneKey = 'incoming_call.ringtone_enabled';
  static const String _vibrationKey = 'incoming_call.vibration_enabled';

  Future<IncomingCallUxSettings> load() async {
    final defaults = IncomingCallUxSettings.defaults;

    final autoOpen = _parseBool(await _secureStorage.read(key: _autoOpenKey));
    final ringtone = _parseBool(await _secureStorage.read(key: _ringtoneKey));
    final vibration = _parseBool(await _secureStorage.read(key: _vibrationKey));

    return IncomingCallUxSettings(
      autoOpenFullScreen: autoOpen ?? defaults.autoOpenFullScreen,
      ringtoneEnabled: ringtone ?? defaults.ringtoneEnabled,
      vibrationEnabled: vibration ?? defaults.vibrationEnabled,
    );
  }

  Future<void> save(IncomingCallUxSettings settings) async {
    await _secureStorage.write(
      key: _autoOpenKey,
      value: settings.autoOpenFullScreen.toString(),
    );
    await _secureStorage.write(
      key: _ringtoneKey,
      value: settings.ringtoneEnabled.toString(),
    );
    await _secureStorage.write(
      key: _vibrationKey,
      value: settings.vibrationEnabled.toString(),
    );
  }

  bool? _parseBool(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    if (value == 'true' || value == '1') return true;
    if (value == 'false' || value == '0') return false;
    return null;
  }
}
