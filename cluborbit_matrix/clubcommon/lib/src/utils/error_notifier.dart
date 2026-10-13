import 'dart:async';

import 'package:flutter/foundation.dart';

class ErrorNotifier extends ChangeNotifier {
  ErrorNotifier._();

  static final ErrorNotifier _instance = ErrorNotifier._();

  factory ErrorNotifier() => _instance;

  /// A connectivity error is usually transient and retried automatically, so it is only shown
  /// once it has failed this many times in a row, or persisted for [releaseConnectivityGrace],
  /// whichever comes first.
  static const int connectivityFailuresBeforeShowing = 5;
  static const Duration releaseConnectivityGrace = Duration(minutes: 1);

  /// What the user is told about a connection outage (the raw error is only logged).
  static const String connectivityAlertMessage =
      "Can't reach the chat server. We'll keep trying - messages send once you're back online.";

  String? _errorMessage;
  bool _isConnectivityError = false;
  DateTime? _connectivityErrorSince;
  int _connectivityFailures = 0;
  Timer? _graceTimer;

  // Which error was last handed out by takeAlert: the outage start for connectivity errors,
  // else the error's serial number.
  Object? _alertedKey;
  int _errorSerial = 0;

  /// The latest error, whether or not it should be shown yet - see [visibleErrorMessage].
  String? get errorMessage => _errorMessage;

  bool get isConnectivityError => _isConnectivityError;

  /// The error to show the user right now, or null. Connectivity errors (no network, server
  /// unreachable, timeouts) are usually transient and retried automatically, so one is only
  /// shown after [connectivityFailuresBeforeShowing] failures in a row or
  /// [releaseConnectivityGrace], as [connectivityAlertMessage]; anything else shows immediately.
  String? get visibleErrorMessage {
    final message = _errorMessage;
    if (message == null || !_isConnectivityError) return message;
    final since = _connectivityErrorSince;
    final persisted =
        _connectivityFailures >= connectivityFailuresBeforeShowing ||
        (since != null &&
            DateTime.now().difference(since) >= releaseConnectivityGrace);
    return persisted ? connectivityAlertMessage : null;
  }

  /// [visibleErrorMessage], but only the first time for each error (and once per connection
  /// outage, however many retries fail): for screens that tell the user with a snackbar, so it
  /// isn't repeated on every retry or by every listening screen. Null otherwise.
  String? takeAlert() {
    final message = visibleErrorMessage;
    if (message == null) return null;
    final key = _isConnectivityError ? _connectivityErrorSince : _errorSerial;
    if (key == _alertedKey) return null;
    _alertedKey = key;
    return message;
  }

  /// `connectivity` marks whether this is a connection problem; left null, it is inferred from
  /// the message.
  void setError(String message, {bool? connectivity}) {
    debugPrint('[ErrorNotifier] $message');
    final isConnectivity = connectivity ?? looksLikeConnectivityError(message);
    _errorMessage = message;
    _isConnectivityError = isConnectivity;
    _errorSerial++;
    if (isConnectivity) {
      // Keep the start of the outage across retries, so the grace period isn't restarted.
      _connectivityErrorSince ??= DateTime.now();
      _connectivityFailures++;
      if (_graceTimer == null) {
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
    _connectivityFailures = 0;
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
