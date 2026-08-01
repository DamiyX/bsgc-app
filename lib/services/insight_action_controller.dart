import 'package:flutter/widgets.dart';

import 'insight_mutation_contract.dart';

Future<bool> persistCommentText(
  TextEditingController controller,
  Future<void> Function(String text) persist, {
  Duration timeout = insightMutationTimeout,
}) async {
  final text = controller.text.trim();
  try {
    await awaitInsightMutation(persist(text), timeout: timeout);
    controller.clear();
    return true;
  } catch (_) {
    return false;
  }
}

class ReversibleToggleController extends ChangeNotifier {
  ReversibleToggleController({
    required bool initialValue,
    this.timeout = insightMutationTimeout,
  }) : _value = initialValue;

  final Duration timeout;

  bool _value;
  bool _isPending = false;
  Object? _lastError;
  bool _disposed = false;

  bool get value => _value;
  bool get isPending => _isPending;
  Object? get lastError => _lastError;

  void _notifyListenersSafely() {
    if (!_disposed) notifyListeners();
  }

  void replaceValue(bool value) {
    if (_isPending || _value == value) return;
    _value = value;
    _lastError = null;
    _notifyListenersSafely();
  }

  Future<bool> setValue(
    bool nextValue,
    Future<void> Function(bool nextValue) persist,
  ) async {
    if (_isPending || _value == nextValue) return false;
    final previousValue = _value;
    _value = nextValue;
    _isPending = true;
    _lastError = null;
    _notifyListenersSafely();
    try {
      await awaitInsightMutation(persist(_value), timeout: timeout);
      return true;
    } catch (error) {
      _value = previousValue;
      _lastError = error;
      return false;
    } finally {
      _isPending = false;
      _notifyListenersSafely();
    }
  }

  Future<bool> toggle(Future<void> Function(bool nextValue) persist) {
    return setValue(!_value, persist);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
