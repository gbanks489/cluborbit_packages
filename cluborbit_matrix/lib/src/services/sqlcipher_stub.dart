/// No-op stub used on platforms where `sqlcipher_flutter_libs` is unavailable.
Future<void> applyWorkaroundToOpenSqlCipherOnOldAndroidVersions() =>
    Future.value();
