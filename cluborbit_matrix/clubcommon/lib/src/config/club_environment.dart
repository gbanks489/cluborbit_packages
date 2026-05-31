typedef EnvReader = String? Function(String key);

class ClubEnvironment {
  const ClubEnvironment._();

  static String _string(
    String key, {
    required EnvReader read,
    String fallback = '',
  }) {
    final value = read(key);
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    return value.trim();
  }

  static bool _bool(
    String key, {
    required EnvReader read,
    required bool fallback,
  }) {
    final value = read(key)?.toLowerCase();
    if (value == null || value.isEmpty) {
      return fallback;
    }
    return value == 'true' || value == '1' || value == 'yes';
  }

  static String matrixHost({
    required EnvReader read,
    required String fallback,
  }) {
    final direct = _string('MATRIX_SERVER', read: read);
    if (direct.isNotEmpty) {
      return direct;
    }

    final chatHost = _string('CHAT_SERVER_HOST', read: read);
    if (chatHost.isNotEmpty) {
      if (chatHost.startsWith('http://') || chatHost.startsWith('https://')) {
        return chatHost;
      }
      final chatHttps = _bool('CHAT_USE_HTTPS', read: read, fallback: true);
      return '${chatHttps ? 'https' : 'http'}://$chatHost';
    }

    return fallback;
  }

  static String serverHost({
    required EnvReader read,
    required String fallback,
  }) => _string('SERVER_HOST', read: read, fallback: fallback);

  static bool serverHttps({required EnvReader read, required bool fallback}) {
    final hasServerHttps = read('SERVER_HTTPS');
    if (hasServerHttps != null) {
      return _bool('SERVER_HTTPS', read: read, fallback: fallback);
    }
    return _bool('USE_HTTPS', read: read, fallback: fallback);
  }

  static String apiVersion({required EnvReader read, String fallback = 'v1'}) =>
      _string('API_VERSION', read: read, fallback: fallback);

  static String serverContextPath({required EnvReader read}) {
    final custom = read('SERVER_CONTEXT_PATH');
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
    }
    return '/playerserver/${apiVersion(read: read)}/api';
  }
}
