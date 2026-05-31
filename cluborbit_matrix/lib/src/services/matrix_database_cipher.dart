/// Legacy hook retained while migrating off Matrix Dart SDK.
///
/// The SDK-free transport path does not use a Matrix SDK database cipher.
Future<String?> getMatrixDatabaseCipher() async {
  return null;
}
