class AuthStateCache {
  AuthStateCache._();

  static final AuthStateCache instance = AuthStateCache._();

  String? _token;
  String? _minAppVersion;
  String? _maxAppVersion;

  String? get token => _token;
  String? get minAppVersion => _minAppVersion;
  String? get maxAppVersion => _maxAppVersion;

  void setToken(String? value) {
    _token = _normalize(value);
  }

  void setVersions({String? minVersion, String? maxVersion}) {
    _minAppVersion = _normalize(minVersion);
    _maxAppVersion = _normalize(maxVersion);
  }

  void clear() {
    _token = null;
    _minAppVersion = null;
    _maxAppVersion = null;
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
