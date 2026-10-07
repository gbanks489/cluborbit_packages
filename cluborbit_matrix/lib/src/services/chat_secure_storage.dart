import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one secure-storage configuration every chat component must use. flutter_secure_storage
/// stores data in two incompatible formats depending on `encryptedSharedPreferences`, and part of
/// the app already uses `true` (see MatrixRestCacheStore), which converts the whole store to that
/// format. An instance with default options in a fresh engine - e.g. the Firebase background
/// isolate handling a push while the app is closed - then reads the old format and finds nothing.
const FlutterSecureStorage chatSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
