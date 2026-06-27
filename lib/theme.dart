import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Colors.black87;
  static const Color offWhite = Color(0xFFFAFAFA);
  static const Color textMain = Colors.black87;
  static const Color textMuted = Colors.black54;
}

final ThemeData appTheme = ThemeData(
  // fontFamily: 'Inter',
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.black87),
  useMaterial3: true,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    iconTheme: IconThemeData(color: Colors.black87),
    titleTextStyle: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600, fontSize: 18),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.black87,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Colors.black87,
    foregroundColor: Colors.white,
  ),
);
