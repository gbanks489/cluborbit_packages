import 'package:flutter/foundation.dart';

class ErrorNotifier extends ChangeNotifier {
  ErrorNotifier._();

  static final ErrorNotifier _instance = ErrorNotifier._();

  factory ErrorNotifier() => _instance;

  String? _errorMessage;

  String? get errorMessage => _errorMessage;

  void setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void clear() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    clear();
  }
}
