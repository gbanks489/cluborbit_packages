import 'dart:async';

import 'package:flutter/foundation.dart';

class ErrorNotifier extends ChangeNotifier {
  ErrorNotifier._();

  static final ErrorNotifier _instance = ErrorNotifier._();

  factory ErrorNotifier() => _instance;

  /// How long a connectivity error must persist (the app keeps retrying meanwhile) before it is
  /// shown in a release build. Debug builds show every error immediately.
  static const Duration releaseConnectivityGrace = Duration(minutes: 1);

  String? _errorMessage;
  bool _isConnectivityError = false;
  DateTime? _connectivityErrorSince;
  Timer? _graceTimer;

  /// The latest error, whether or not it should be shown yet - see [visibleErrorMessage].
  String? get errorMessage => _errorMessage;

  bool get isConnectivityError => _isConnectivityError;

  /// The error to show the user right now, or null. Connectivity errors (no network, server
  /// unreachable, timeouts) are usually transient and retried automatically, so a release build
  /// only shows one once it has persisted for [releaseConnectivityGrace]; anything else - and
  /// everything in a debug build - shows immediately.
  String? get visibleErrorMessage {
    final message = _errorMessage;
    if (message == null || kDebugMode || !_isConnectivityError) return message;
    final since = _connectivityErrorSince;
    if (since != null &&
        DateTime.now().difference(since) >= releaseConnectivityGrace) {
      return message;
    }
    return null;
  }

  /// `connectivity` marks whether this is a connection problem; left null, it is inferred from
  /// the message.
  void setError(String message, {bool? connectivity}) {
    debugPrint('[ErrorNotifier] $message');
    final isConnectivity = connectivity ?? looksLikeConnectivityError(message);
    _errorMessage = message;
    _isConnectivityError = isConnectivity;
    if (isConnectivity) {
      // Keep the start of the outage across retries, so the grace period isn't restarted.
      _connectivityErrorSince ??= DateTime.now();
      if (!kDebugMode && _graceTimer == null) {
        final remaining =
            releaseConnectivityGrace -
            DateTime.now().difference(_connectivityErrorSince!);
        _graceTimer = Timer(
          remaining.isNegative ? Duration.zero : remaining,
          () {
            _graceTimer = null;
            // Re-evaluate visibleErrorMessage now that the grace period is over.
            if (_isConnectivityError) notifyListeners();
          },
        );
      }
    } else {
      _resetConnectivityTracking();
    }
    notifyListeners();
  }

  void clear() {
    _errorMessage = null;
    _isConnectivityError = false;
    _resetConnectivityTracking();
    notifyListeners();
  }

  void clearError() {
    clear();
  }

  /// Clears the current error only if it's a connectivity one - call when the connection is
  /// known to be working again (e.g. a sync succeeded), so a recovered outage isn't shown later.
  void clearConnectivityError() {
    if (_errorMessage != null && _isConnectivityError) {
      clear();
    } else if (_errorMessage == null && _connectivityErrorSince != null) {
      _resetConnectivityTracking();
    }
  }

  void _resetConnectivityTracking() {
    _connectivityErrorSince = null;
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  static bool looksLikeConnectivityError(String message) {
    final text = message.toLowerCase();
    const markers = <String>[
      'socketexception',
      'failed host lookup',
      'connection refused',
      'connection reset',
      'connection closed',
      'connection failed',
      'connection timed out',
      'network is unreachable',
      'no address associated',
      'clientexception',
      'handshakeexception',
      'timeoutexception',
      'timed out',
      'timeout',
      'check your internet',
      'no internet',
      'chat connection failed',
      'http 502',
      'http 503',
      'http 504',
    ];
    return markers.any(text.contains);
  }
}
