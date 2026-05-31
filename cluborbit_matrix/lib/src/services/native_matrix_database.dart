/// Legacy hook retained for backward compatibility.
///
/// The SDK-free Matrix transport no longer requires a Matrix SDK database,
/// so this returns `null`.
Future<Object?> buildNativeMatrixDatabase(String databaseName) async {
  return null;
}
