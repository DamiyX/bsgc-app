import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChatBubbleTheme { gradient, solidPurple, lightGray, dark, darkGray }

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ChatBubbleTheme _chatBubbleTheme = ChatBubbleTheme.gradient;

  ThemeMode get themeMode => _themeMode;
  ChatBubbleTheme get chatBubbleTheme => _chatBubbleTheme;

  ThemeProvider([SharedPreferences? prefs]) {
    if (prefs != null) _loadTheme(prefs);
  }

  Future<void> load() async {
    try {
      _loadTheme(await SharedPreferences.getInstance());
      notifyListeners();
    } catch (_) {
      // The default light theme remains usable when preferences are unavailable.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', mode.toString());
    } catch (_) {
      // Keep the in-memory selection for this session.
    }
  }

  Future<void> setChatBubbleTheme(ChatBubbleTheme theme) async {
    _chatBubbleTheme = theme;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('chat_bubble_theme', theme.index);
    } catch (_) {
      // Keep the in-memory selection for this session.
    }
  }

  void _loadTheme(SharedPreferences prefs) {
    final savedMode = prefs.getString('theme_mode');

    int? themeIndex = prefs.getInt('chat_bubble_theme');
    if (themeIndex != null &&
        themeIndex >= 0 &&
        themeIndex < ChatBubbleTheme.values.length) {
      _chatBubbleTheme = ChatBubbleTheme.values[themeIndex];
    } else {
      bool useSimple = prefs.getBool('use_simple_chat_color') ?? false;
      _chatBubbleTheme = useSimple
          ? ChatBubbleTheme.lightGray
          : ChatBubbleTheme.gradient;
    }

    if (savedMode != null) {
      if (savedMode == ThemeMode.dark.toString()) {
        _themeMode = ThemeMode.dark;
      } else if (savedMode == ThemeMode.system.toString()) {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light;
      }
    }
  }
}
