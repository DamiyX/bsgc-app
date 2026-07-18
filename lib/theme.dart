import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const Color primary = Color(0xFF2A2A2A); // Charcoal
  static const Color offWhite = Color(0xFFFFFFFF); // Pure white
  static const Color textMain = Color(0xFF2A2A2A); // Charcoal
  static const Color textMuted = Color(0xFF757575);
  static const Color gradientStart = Color(0xFFD4B8FB);
  static const Color gradientEnd = Color(0xFF8E54E9);
  static const Color chatBubbleGradientStart = Color(0xFF8E2DE2);
  static const Color chatBubbleGradientEnd = Color(0xFF4A00E0);
  static const Color calendarSoftPurple = Color(0xFFF3E5F5); // Soft light purple
}

final ThemeData appTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    secondary: AppColors.gradientStart,
    surface: AppColors.offWhite,
    onSurface: AppColors.textMain,
    onSurfaceVariant: Colors.black54,
    surfaceContainer: Colors.grey.shade100,
    surfaceContainerHighest: Colors.grey.shade200,
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.gradientEnd),
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.offWhite,
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Color(0xFF323232),
    contentTextStyle: TextStyle(color: Colors.white),
    actionTextColor: AppColors.gradientStart,
  ),
  dividerColor: Colors.grey.shade300,
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: AppColors.gradientStart,
    selectionColor: AppColors.gradientStart,
    selectionHandleColor: AppColors.gradientStart,
  ),
  inputDecorationTheme: InputDecorationTheme(
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: AppColors.gradientStart, width: 2.0),
      borderRadius: BorderRadius.circular(12),
    ),
    floatingLabelStyle: TextStyle(color: AppColors.gradientStart),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    iconTheme: IconThemeData(color: AppColors.primary),
    titleTextStyle: TextStyle(
      color: AppColors.textMain, 
      fontWeight: FontWeight.w700, 
      fontSize: 18,
    ),
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), // Squircle radius
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      elevation: 0, // Neobrutalist design usually handles shadow explicitly if needed
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    shape: CircleBorder(), // Circle radius 50%
  ),
);

final ThemeData darkAppTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    brightness: Brightness.dark,
    seedColor: AppColors.primary,
    secondary: AppColors.gradientStart,
    surface: const Color(0xFF1E1E1E), // Slightly lighter than scaffold for cards
    onSurface: Colors.white,
    onSurfaceVariant: Colors.white70,
    surfaceContainer: const Color(0xFF2C2C2C), // Input backgrounds
    surfaceContainerHighest: const Color(0xFF383838), // Slightly lighter backgrounds
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.gradientEnd),
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.black,
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Color(0xFF323232),
    contentTextStyle: TextStyle(color: Colors.white),
    actionTextColor: AppColors.gradientStart,
  ),
  dividerColor: Colors.grey.shade900,
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: AppColors.gradientStart,
    selectionColor: AppColors.gradientStart,
    selectionHandleColor: AppColors.gradientStart,
  ),
  inputDecorationTheme: InputDecorationTheme(
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: AppColors.gradientStart, width: 2.0),
      borderRadius: BorderRadius.circular(12),
    ),
    floatingLabelStyle: TextStyle(color: AppColors.gradientStart),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    iconTheme: IconThemeData(color: Colors.white),
    titleTextStyle: TextStyle(
      color: Colors.white, 
      fontWeight: FontWeight.w700, 
      fontSize: 18,
    ),
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      elevation: 0,
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    shape: CircleBorder(),
  ),
);
