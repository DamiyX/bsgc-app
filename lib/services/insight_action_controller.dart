import 'package:flutter/widgets.dart';

Future<bool> persistCommentText(
  TextEditingController controller,
  Future<void> Function(String text) persist,
) async {
  final text = controller.text.trim();
  try {
    await persist(text);
    controller.clear();
    return true;
  } catch (_) {
    return false;
  }
}

class ReversibleToggleController extends ChangeNotifier {
  ReversibleToggleController({required bool initialValue})
    : _value = initialValue;

  bool _value;
  bool _isPending = false;
  Object? _lastError;

  bool get value => _value;
  bool get isPending => _isPending;
  Object? get lastError => _lastError;

  void replaceValue(bool value) {
    if (_isPending || _value == value) return;
    _value = value;
    _lastError = null;
    notifyListeners();
  }

  Future<bool> toggle(Future<void> Function(bool nextValue) persist) async {
    if (_isPending) return false;
    final previousValue = _value;
    _value = !previousValue;
    _isPending = true;
    _lastError = null;
    notifyListeners();
    try {
      await persist(_value);
      return true;
    } catch (error) {
      _value = previousValue;
      _lastError = error;
      return false;
    } finally {
      _isPending = false;
      notifyListeners();
    }
  }
}
