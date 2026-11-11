import 'package:flutter/material.dart';

abstract final class HomaGramTheme {
  static const Color navy = Color(0xFF101B35);
  static const Color turquoise = Color(0xFF20B8B0);
  static const Color royalPurple = Color(0xFF7356C8);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: turquoise,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE8ECF3)),
        ),
      ),
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: turquoise,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B1224),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF141F36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF26334D)),
        ),
      ),
    );
  }
}
