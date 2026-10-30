import 'package:flutter/material.dart';

/// Зимняя тема: тёмно-синий фон и ледяные акценты.
class W {
  static const bg = Color(0xFF0A1020);
  static const surface = Color(0xFF111A2E);
  static const surface2 = Color(0xFF17223A);
  static const border = Color(0xFF24324F);
  static const text = Color(0xFFEAF2FF);
  static const muted = Color(0xFF8A9BB8);
  static const ice = Color(0xFF7FD8FF);
  static const iceLight = Color(0xFFC8EEFF);
  static const good = Color(0xFF5EE6A8);
  static const warn = Color(0xFFFFC46B);
  static const bad = Color(0xFFFF6B8A);

  static const h1 = TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: text, letterSpacing: -0.5);
  static const h2 = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text);
  static const body = TextStyle(fontSize: 14, color: text, height: 1.35);
  static const small = TextStyle(fontSize: 12.5, color: muted, height: 1.35);
}

ThemeData buildTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: W.bg,
      colorScheme: const ColorScheme.dark(primary: W.ice, secondary: W.iceLight, surface: W.surface),
      useMaterial3: true,
      snackBarTheme: const SnackBarThemeData(backgroundColor: W.surface2, contentTextStyle: TextStyle(color: W.text)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: W.ice),
    );

Color hexColor(String s, [Color fallback = W.ice]) {
  final h = s.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}
