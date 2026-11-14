import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// System-font hierarchy shared by the main pages. No bundled font family.
abstract final class BingoTypography {
  static const pageTitle = TextStyle(
      fontSize: 18, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: 0);
  static const sectionTitle = TextStyle(
      fontSize: 18,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: 0);
  static const itemTitle = TextStyle(
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: 0);
  static const menuTitle = TextStyle(
      fontSize: 16, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0);
  static const profileName = TextStyle(
      fontSize: 20,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: 0);
  static const body = TextStyle(
      fontSize: 14, height: 1.5, fontWeight: FontWeight.w400, letterSpacing: 0);
  static const secondary = TextStyle(
      fontSize: 14, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0);
  static const caption = TextStyle(
      fontSize: 12,
      height: 1.35,
      fontWeight: FontWeight.w400,
      letterSpacing: 0);
}

abstract final class BingoPalette {
  static const ink = Color(0xFF262626);
  static const primary = Color(0xFFEE5B88);
  static const primaryText = Color(0xFFB92E5B);
  static const sage = Color(0xFFEE5B88);
  static const muted = Color(0xFF737373);
  static const surface = Colors.white;
  static const pageTop = Colors.white;
  static const pageBottom = Color(0xFFFFFFFF);
  static const rose = Color(0xFFF45D88);
  static const gold = Color(0xFFE6A342);
  static const lavender = Color(0xFFEE5B88);
  static const blue = primary;
  static const cyan = Color(0xFFE9A3B6);
  static const violet = sage;
  static const blush = Color(0xFFF7F7F7);
  static const ice = Colors.white;
  static const line = Color(0xFFF0F0F0);
  static const softSurface = Color(0xFFFAFAFA);
  static const voiceSurface = Color(0xFFF7F7F7);
  // Conversation colors remain independent of the app's navigation accent.
  static const userBubble = Color(0xFFE7FECC);
  static const userBubbleBorder = Color(0xFFB7C4CA);
  static const online = Color(0xFF63BB68);
  static const accentBorder = Color(0xFFEFEFEF);
  static const avatarButton = blush;
  static const avatarButtonInk = primary;
  static const mintBackground = ice;
  static const mintTint = blush;
  static const mintPrimary = primary;
  static const chatMenuSurface = surface;
  static const chatMenuInk = primary;
  static const chatMenuBorder = line;
  static const companionActionSurface = blush;
  static const companionActionInk = primary;
  static const companionActionIcon = primary;
  static const companionActionBorder = accentBorder;

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sage, primary],
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
    colors: [blush, Color(0x00FBE9EF)],
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
    outline: const Color(0xFFE4E4E4),
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
    textTheme: base.textTheme
        .copyWith(
          titleLarge:
              base.textTheme.titleLarge?.merge(BingoTypography.pageTitle),
          titleMedium:
              base.textTheme.titleMedium?.merge(BingoTypography.sectionTitle),
          titleSmall:
              base.textTheme.titleSmall?.merge(BingoTypography.itemTitle),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
              fontSize: 16, height: 1.5, fontWeight: FontWeight.w400),
          bodyMedium: base.textTheme.bodyMedium?.merge(BingoTypography.body),
          bodySmall: base.textTheme.bodySmall?.merge(BingoTypography.caption),
          labelLarge: base.textTheme.labelLarge?.copyWith(
              fontSize: 14, height: 1.4, fontWeight: FontWeight.w500),
        )
        .apply(
          bodyColor: colors.onSurface,
          displayColor: colors.onSurface,
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
          fontSize: 18,
          height: 1.3,
          fontWeight: FontWeight.w500,
          color: BingoPalette.ink),
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
      fillColor: BingoPalette.softSurface,
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
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: BingoPalette.ink,
        side: const BorderSide(color: BingoPalette.accentBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: BingoPalette.softSurface,
      selectedColor: const Color(0xFFFFF0F5),
      side: const BorderSide(color: BingoPalette.accentBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(fontSize: 13, color: BingoPalette.ink),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      showCheckmark: false,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 12,
      iconColor: BingoPalette.ink,
      titleTextStyle:
          TextStyle(fontSize: 15, height: 1.4, color: BingoPalette.ink),
      subtitleTextStyle:
          TextStyle(fontSize: 12, height: 1.5, color: BingoPalette.muted),
    ),
    dividerTheme: const DividerThemeData(
        color: BingoPalette.line, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 14, color: BingoPalette.ink),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: BingoPalette.ink,
      unselectedLabelColor: BingoPalette.muted,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      unselectedLabelStyle:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
      indicatorColor: BingoPalette.primary,
      dividerColor: BingoPalette.line,
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
          fontSize: 18,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: BingoPalette.ink),
      contentTextStyle:
          const TextStyle(fontSize: 14, height: 1.6, color: BingoPalette.muted),
    ),
    cardTheme: CardThemeData(
      color: BingoPalette.surface.withValues(alpha: 0.96),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: BingoPalette.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
