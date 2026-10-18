import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:clubcommon/clubcommon.dart' show AuthStateCache, ErrorNotifier;

class AuthService {
  AuthService({ErrorNotifier? errorNotifier})
    : _errorNotifier = errorNotifier,
      _cachedToken = AuthStateCache.instance.token {
    authStateChanges.listen((user) async {
      if (user == null) {
        _setCachedToken(null);
        return;
      }

      await getToken();
    });
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  ErrorNotifier? _errorNotifier;
  String? _cachedToken;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;
  String? get cachedToken => AuthStateCache.instance.token ?? _cachedToken;
  String? get minAppVersion => AuthStateCache.instance.minAppVersion;
  String? get maxAppVersion => AuthStateCache.instance.maxAppVersion;

  set errorNotifier(ErrorNotifier notifier) => _errorNotifier = notifier;

  Future<String?> getToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      _setCachedToken(null);
      return null;
    }

    // Reuse the cached token only while it's still good: it lives across app resumes, so after
    // a while in the background (e.g. opening a notification hours later) it has expired, and
    // sending it made the first request fail with an invalid-token error.
    if (!forceRefresh && _isFresh(_cachedToken)) {
      return _cachedToken;
    }

    final token = await user.getIdToken(forceRefresh);
    _setCachedToken(token);
    return _cachedToken;
  }

  void cacheAppVersions({String? minVersion, String? maxVersion}) {
    AuthStateCache.instance.setVersions(
      minVersion: _normalize(minVersion),
      maxVersion: _normalize(maxVersion),
    );
  }

  Future<UserCredential?> loginUserWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await getToken(forceRefresh: true);
      _errorNotifier?.clear();
      return credential;
    } on FirebaseAuthException catch (e) {
      _errorNotifier?.setError(e.message ?? 'Firebase auth error');
      rethrow;
    }
  }

  Future<UserCredential?> registerWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await getToken(forceRefresh: true);
      _errorNotifier?.clear();
      return credential;
    } on FirebaseAuthException catch (e) {
      _errorNotifier?.setError(e.message ?? 'Firebase registration error');
      rethrow;
    }
  }

  Future<UserCredential?> googleLogin() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await account.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final firebaseCredential = await _auth.signInWithCredential(credential);
      await getToken(forceRefresh: true);
      _errorNotifier?.clear();
      return firebaseCredential;
    } catch (e) {
      _errorNotifier?.setError('Google sign-in failed: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    _setCachedToken(null);
    cacheAppVersions();
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// True when [token] is a JWT that won't expire in the next 5 minutes.
  static bool _isFresh(String? token) {
    if (token == null || token.isEmpty) return false;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return false;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 5)));
    } catch (_) {
      return false;
    }
  }

  void _setCachedToken(String? token) {
    _cachedToken = _normalize(token);
    AuthStateCache.instance.setToken(_cachedToken);
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
