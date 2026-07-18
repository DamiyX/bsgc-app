import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChatBubbleTheme { gradient, solidPurple, lightGray, dark }

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ChatBubbleTheme _chatBubbleTheme = ChatBubbleTheme.gradient;

  ThemeMode get themeMode => _themeMode;
  ChatBubbleTheme get chatBubbleTheme => _chatBubbleTheme;

  ThemeProvider() {
    _loadTheme();
  }

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.toString());
  }

  void setChatBubbleTheme(ChatBubbleTheme theme) async {
    _chatBubbleTheme = theme;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('chat_bubble_theme', theme.index);
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('theme_mode');
    
    int? themeIndex = prefs.getInt('chat_bubble_theme');
    if (themeIndex != null && themeIndex >= 0 && themeIndex < ChatBubbleTheme.values.length) {
      _chatBubbleTheme = ChatBubbleTheme.values[themeIndex];
    } else {
      bool useSimple = prefs.getBool('use_simple_chat_color') ?? false;
      _chatBubbleTheme = useSimple ? ChatBubbleTheme.solidGray : ChatBubbleTheme.gradient;
    }

    if (savedMode != null) {
      if (savedMode == ThemeMode.dark.toString()) {
        _themeMode = ThemeMode.dark;
      } else if (savedMode == ThemeMode.system.toString()) {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light;
      }
      notifyListeners();
    } else {
      notifyListeners();
    }
  }
}
