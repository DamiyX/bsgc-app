import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const Color primary = Color(0xFF5E3A70);
  static const Color offWhite = Color(0xFFFFFBF5);
  static const Color textMain = Color(0xFF241C25);
  static const Color textMuted = Color(0xFF6F6670);
  static const Color gradientStart = Color(0xFFD7C1DE);
  static const Color gradientEnd = Color(0xFF6E477E);
  static const Color chatBubbleGradientStart = Color(0xFF76518A);
  static const Color chatBubbleGradientEnd = Color(0xFF563466);
  static const Color calendarSoftPurple = Color(0xFFF2EAF4);
}

@immutable
class BraidSemanticColors extends ThemeExtension<BraidSemanticColors> {
  final Color scriptureSurface;
  final Color scriptureText;
  final Color privateAudience;
  final Color contactsAudience;
  final Color groupAudience;
  final Color pending;
  final Color offline;
  final Color success;
  final Color warning;
  final Color focus;

  const BraidSemanticColors({
    required this.scriptureSurface,
    required this.scriptureText,
    required this.privateAudience,
    required this.contactsAudience,
    required this.groupAudience,
    required this.pending,
    required this.offline,
    required this.success,
    required this.warning,
    required this.focus,
  });

  @override
  BraidSemanticColors copyWith({
    Color? scriptureSurface,
    Color? scriptureText,
    Color? privateAudience,
    Color? contactsAudience,
    Color? groupAudience,
    Color? pending,
    Color? offline,
    Color? success,
    Color? warning,
    Color? focus,
  }) {
    return BraidSemanticColors(
      scriptureSurface: scriptureSurface ?? this.scriptureSurface,
      scriptureText: scriptureText ?? this.scriptureText,
      privateAudience: privateAudience ?? this.privateAudience,
      contactsAudience: contactsAudience ?? this.contactsAudience,
      groupAudience: groupAudience ?? this.groupAudience,
      pending: pending ?? this.pending,
      offline: offline ?? this.offline,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      focus: focus ?? this.focus,
    );
  }

  @override
  BraidSemanticColors lerp(
    covariant BraidSemanticColors? other,
    double t,
  ) {
    if (other == null) return this;
    return BraidSemanticColors(
      scriptureSurface: Color.lerp(scriptureSurface, other.scriptureSurface, t)!,
      scriptureText: Color.lerp(scriptureText, other.scriptureText, t)!,
      privateAudience: Color.lerp(privateAudience, other.privateAudience, t)!,
      contactsAudience: Color.lerp(
        contactsAudience,
        other.contactsAudience,
        t,
      )!,
      groupAudience: Color.lerp(groupAudience, other.groupAudience, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
    );
  }
}

const _lightSemanticColors = BraidSemanticColors(
  scriptureSurface: Color(0xFFF4EBDD),
  scriptureText: Color(0xFF493927),
  privateAudience: Color(0xFF6C5A73),
  contactsAudience: Color(0xFF336B87),
  groupAudience: Color(0xFF5E3A70),
  pending: Color(0xFF9A6B22),
  offline: Color(0xFF5D6670),
  success: Color(0xFF3F7652),
  warning: Color(0xFFA15C19),
  focus: Color(0xFF336B87),
);

const _darkSemanticColors = BraidSemanticColors(
  scriptureSurface: Color(0xFF352E25),
  scriptureText: Color(0xFFF3E5D0),
  privateAudience: Color(0xFFCDB7D5),
  contactsAudience: Color(0xFF91C7DF),
  groupAudience: Color(0xFFD8B8E3),
  pending: Color(0xFFF0C26B),
  offline: Color(0xFFB7C0C8),
  success: Color(0xFF91C8A2),
  warning: Color(0xFFF0B16F),
  focus: Color(0xFF91C7DF),
);

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: AppColors.primary,
    primary: isDark ? const Color(0xFFD8B8E3) : AppColors.primary,
    secondary: isDark
        ? const Color(0xFF9EC2A5)
        : const Color(0xFF4F7658),
    surface: isDark ? const Color(0xFF1D191E) : AppColors.offWhite,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF151216)
        : AppColors.offWhite,
    extensions: [
      isDark ? _darkSemanticColors : _lightSemanticColors,
    ],
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
    ),
    dividerColor: scheme.outlineVariant,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark
          ? const Color(0xFF332D34)
          : const Color(0xFF332C34),
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: const Color(0xFFE8CFF0),
      behavior: SnackBarBehavior.floating,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.24),
      selectionHandleColor: scheme.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      floatingLabelStyle: TextStyle(color: scheme.primary),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: scheme.onSurface),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(48, 48),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: const CircleBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
  );
}

final ThemeData appTheme = _buildTheme(Brightness.light);
final ThemeData darkAppTheme = _buildTheme(Brightness.dark);
