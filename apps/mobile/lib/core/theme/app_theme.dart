import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class BingoPalette {
  static const ink = Color(0xFF182D29);
  static const primary = Color(0xFF00A786);
  static const primaryText = Color(0xFF08775D);
  static const sage = Color(0xFF20C5A6);
  static const muted = Color(0xFF67778E);
  static const surface = Colors.white;
  static const pageTop = Color(0xFFEAFBF7);
  static const pageBottom = Color(0xFFF2FBF9);
  static const rose = Color(0xFFF45D88);
  static const gold = Color(0xFFE6A342);
  static const lavender = Color(0xFF8B73D9);
  static const blue = primary;
  static const cyan = Color(0xFF67D8C2);
  static const violet = sage;
  static const blush = Color(0xFFDDF9F2);
  static const ice = Color(0xFFF7FBFA);
  static const line = Color(0xFFEAF0F3);
  static const softSurface = Color(0xFFF0FAF7);
  static const userBubble = Color(0xFFCAFAEC);
  static const avatarButton = blush;
  static const avatarButtonInk = primary;
  static const mintBackground = ice;
  static const mintTint = blush;
  static const mintPrimary = primary;
  static const chatMenuSurface = surface;
  static const chatMenuInk = primary;
  static const chatMenuBorder = line;
  static const companionActionSurface = Color(0xFFDDF9F2);
  static const companionActionInk = primary;
  static const companionActionIcon = primary;
  static const companionActionBorder = Color(0xFFB7EEE0);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF20C9AA), primary],
  );

  static const softGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surface, ice, pageBottom],
  );

  static const companionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surface, ice],
  );

  static const companionGlow = RadialGradient(
    center: Alignment(0.9, -1),
    radius: 1,
    colors: [Color(0xFFDDF9F2), Color(0x00DDF9F2)],
  );
}

ButtonStyle companionActionButtonStyle({double height = 54}) =>
    FilledButton.styleFrom(
        backgroundColor: BingoPalette.companionActionSurface,
        foregroundColor: BingoPalette.companionActionInk,
        minimumSize: Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        side: const BorderSide(color: BingoPalette.companionActionBorder),
        shape: const StadiumBorder());

ThemeData buildMintTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.copyWith(
      scaffoldBackgroundColor: BingoPalette.mintBackground,
      colorScheme: theme.colorScheme.copyWith(
          primary: BingoPalette.mintPrimary,
          onPrimary: Colors.white,
          primaryContainer: BingoPalette.mintTint,
          onPrimaryContainer: BingoPalette.mintPrimary),
      filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.disabled)
                      ? theme.filledButtonTheme.style?.backgroundColor
                          ?.resolve(states)
                      : BingoPalette.mintPrimary))));
}

ThemeData buildBingoTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: BingoPalette.blue,
    brightness: Brightness.light,
    surface: BingoPalette.surface,
  ).copyWith(
    primary: BingoPalette.blue,
    secondary: BingoPalette.violet,
    onSurface: BingoPalette.ink,
    outline: const Color(0xFFB8CFC9),
    outlineVariant: BingoPalette.line,
    surfaceContainer: BingoPalette.softSurface,
    surfaceContainerHigh: BingoPalette.blush,
  );
  final base = ThemeData(
    colorScheme: colors,
    useMaterial3: true,
  );
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
      titleTextStyle: const TextStyle(
          fontSize: 19, fontWeight: FontWeight.w800, color: BingoPalette.ink),
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
      fillColor: BingoPalette.surface.withValues(alpha: 0.9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      prefixIconColor: BingoPalette.muted,
      suffixIconColor: BingoPalette.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: BingoPalette.ink),
      contentTextStyle:
          const TextStyle(fontSize: 14, height: 1.6, color: BingoPalette.muted),
    ),
    cardTheme: CardThemeData(
      color: BingoPalette.surface.withValues(alpha: 0.96),
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
