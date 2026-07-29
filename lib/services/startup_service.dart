import 'dart:async';

import 'package:flutter/foundation.dart';

enum StartupStatus { idle, loading, ready, failed }

class StartupController extends ChangeNotifier {
  final Future<void> Function() initialize;
  final Duration timeout;

  StartupController({
    required this.initialize,
    this.timeout = const Duration(seconds: 15),
  });

  StartupStatus _status = StartupStatus.idle;
  Object? _error;
  int _attempt = 0;

  StartupStatus get status => _status;
  Object? get error => _error;

  Future<void> start() async {
    final attempt = ++_attempt;
    _status = StartupStatus.loading;
    _error = null;
    notifyListeners();
    try {
      await initialize().timeout(timeout);
      if (attempt != _attempt) return;
      _status = StartupStatus.ready;
    } catch (error) {
      if (attempt != _attempt) return;
      _status = StartupStatus.failed;
      _error = error;
    }
    notifyListeners();
  }

  Future<void> retry() => start();
}
