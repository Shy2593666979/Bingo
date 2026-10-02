import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class BingoPalette {
  static const ink = Color(0xFF172723);
  static const blue = Color(0xFF08775D);
  static const cyan = Color(0xFF67CDAE);
  static const violet = Color(0xFF35A980);
  static const blush = Color(0xFFE4F7F0);
  static const ice = Color(0xFFF9FCFB);
  static const line = Color(0xFFE3EEEA);
  static const softSurface = Color(0xFFEDF5F2);
  static const userBubble = Color(0xFFD5F0E3);
  static const avatarButton = Color(0xFFDDF2E7);
  static const avatarButtonInk = Color(0xFF4F8067);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF08775D), Color(0xFF35A980)],
  );

  static const softGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF3FBF8), Color(0xFFFBFDFC)],
  );

  static const companionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8FDFC), Color(0xFFF3FBF7)],
  );

  static const companionGlow = RadialGradient(
    center: Alignment(0.9, -1),
    radius: 1,
    colors: [Color(0xFFE6F7ED), Color(0x00E6F7ED)],
  );
}

ThemeData buildBingoTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: BingoPalette.blue,
    brightness: Brightness.light,
    surface: Colors.white,
  ).copyWith(
    primary: BingoPalette.blue,
    secondary: BingoPalette.violet,
    onSurface: BingoPalette.ink,
    outline: const Color(0xFFCBD9D4),
    outlineVariant: BingoPalette.line,
    surfaceContainer: const Color(0xFFF0F7F4),
    surfaceContainerHigh: const Color(0xFFE9F3EF),
  );
  final base = ThemeData(colorScheme: colors, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: BingoPalette.ice,
    textTheme: base.textTheme.apply(
      bodyColor: colors.onSurface,
      displayColor: colors.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: colors.onSurface,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      prefixIconColor: const Color(0xFF69718B),
      suffixIconColor: const Color(0xFF69718B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colors.error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: 0.92),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: BingoPalette.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
