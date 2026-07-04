import 'package:flutter/material.dart';

enum InsightThemeType { gradient, image }

class InsightTheme {
  final String id;
  final InsightThemeType type;
  final String label;
  final List<Color>? gradientColors;
  final String? imageUrl;
  final Color baseColor; // Used for UI elements and fallbacks

  const InsightTheme({
    required this.id,
    required this.type,
    required this.label,
    this.gradientColors,
    this.imageUrl,
    required this.baseColor,
  });
}

class InsightThemes {
  static const List<InsightTheme> themes = [
    InsightTheme(
      id: 'theme_0',
      type: InsightThemeType.gradient,
      label: 'Dawn',
      gradientColors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // Purple gradient
      baseColor: Color(0xFF4A00E0),
    ),
    InsightTheme(
      id: 'theme_1',
      type: InsightThemeType.gradient,
      label: 'Ocean',
      gradientColors: [Color(0xFF2193b0), Color(0xFF6dd5ed)], // Blue gradient
      baseColor: Color(0xFF2193b0),
    ),
    InsightTheme(
      id: 'theme_2',
      type: InsightThemeType.gradient,
      label: 'Sunset',
      gradientColors: [Color(0xFFFF512F), Color(0xFFDD2476)], // Orange/Pink gradient
      baseColor: Color(0xFFDD2476),
    ),
    InsightTheme(
      id: 'theme_3',
      type: InsightThemeType.image,
      label: 'Forest',
      imageUrl: 'https://images.unsplash.com/photo-1473448912268-2022ce9509d8?w=800&q=80',
      baseColor: Color(0xFF1B5E20),
    ),
    InsightTheme(
      id: 'theme_4',
      type: InsightThemeType.image,
      label: 'Minimal',
      imageUrl: 'https://images.unsplash.com/photo-1517409249764-7d5a570c1844?w=800&q=80',
      baseColor: Color(0xFF757575),
    ),
    InsightTheme(
      id: 'theme_5',
      type: InsightThemeType.image,
      label: 'Texture',
      imageUrl: 'https://images.unsplash.com/photo-1518606894874-98c4fb24e41b?w=800&q=80',
      baseColor: Color(0xFF5D4037),
    ),
  ];

  static InsightTheme getThemeById(String id) {
    return themes.firstWhere(
      (theme) => theme.id == id,
      orElse: () => themes.first,
    );
  }
}
