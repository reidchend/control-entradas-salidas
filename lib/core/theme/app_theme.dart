import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Puerto de `apply_theme_to_*` de usr/theme.py a un ThemeData de Material 3
/// con paleta morada/púrpura y complementarios.
AppThemeData buildAppTheme({required ThemeMode mode}) {
  final isDark = mode == ThemeMode.dark;
  final c = AppColors.of(isDark);
  Color col(String key) =>
      Color(int.parse(c[key]!.replaceFirst('#', '0xFF')));

  final accent = col('accent');
  final secondary = col('accent_dark');
  final tertiary = col('tertiary');
  final surface = col('surface');
  final textPrimary = col('text_primary');
  final textSecondary = col('text_secondary');
  final error = col('error');

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: isDark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: accent,
    onPrimary: col('white'),
    primaryContainer: col('accent_container'),
    onPrimaryContainer: col('on_accent_container'),
    secondary: secondary,
    onSecondary: Colors.white,
    secondaryContainer:
        Color.alphaBlend(secondary.withValues(alpha: 0.18), surface),
    onSecondaryContainer: textPrimary,
    tertiary: tertiary,
    onTertiary: Colors.white,
    tertiaryContainer:
        Color.alphaBlend(tertiary.withValues(alpha: 0.16), surface),
    onTertiaryContainer: textPrimary,
    error: error,
    onError: Colors.white,
    errorContainer: col('red_50'),
    onErrorContainer: error,
    surface: surface,
    onSurface: textPrimary,
    onSurfaceVariant: textSecondary,
    outline: col('border'),
    outlineVariant: col('input_border'),
    surfaceContainer: col('card'),
    surfaceContainerHigh: col('card_hover'),
    surfaceContainerHighest: col('surface_variant'),
    surfaceTint: accent,
    inverseSurface: isDark ? const Color(0xFFE6E0E9) : const Color(0xFF2B2640),
    onInverseSurface: isDark ? const Color(0xFF2B2640) : const Color(0xFFF4F0FF),
    inversePrimary: isDark ? const Color(0xFFD0B6FF) : const Color(0xFFBB86FC),
    shadow: isDark ? Colors.black : const Color(0xFF2E2560),
    scrim: col('black'),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: col('bg'),
  );

  final textTheme = base.textTheme.copyWith(
    headlineSmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: textPrimary,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.35,
      color: textPrimary,
    ),
    bodySmall: TextStyle(fontSize: 12, height: 1.3, color: textSecondary),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  const buttonPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 14,
  );

  return AppThemeData(
    isDark: isDark,
    colors: c,
    theme: base.copyWith(
      textTheme: textTheme,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.30),
        selectionHandleColor: accent,
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: col('header_bg'),
        foregroundColor: col('header_title'),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: col('header_title'),
        ),
        iconTheme: IconThemeData(color: col('header_icon')),
      ),
      cardTheme: CardThemeData(
        color: col('card'),
        margin: EdgeInsets.zero,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: col('border')),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: col('input_bg'),
        hintStyle: TextStyle(color: col('input_hint')),
        labelStyle: TextStyle(color: textSecondary),
        floatingLabelStyle: TextStyle(color: accent),
        helperStyle: TextStyle(color: textSecondary),
        prefixIconColor: col('text_hint'),
        suffixIconColor: col('text_hint'),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: col('input_border')),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: col('white'),
          elevation: 0,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: col('white'),
          elevation: 1,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: col('input_border')),
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: col('white'),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: col('surface'),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: col('surface'),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: col('drawer_bg'),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: col('nav_bg'),
        indicatorColor: col('drawer_active_bg'),
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? col('accent') : col('text_hint'),
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? textPrimary : col('text_hint'),
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: textSecondary,
        indicatorColor: accent,
        dividerColor: col('border'),
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: col('surface_variant'),
        selectedColor: col('accent_container'),
        disabledColor: col('surface_variant'),
        side: BorderSide(color: col('border')),
        labelStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
        secondaryLabelStyle: TextStyle(color: textSecondary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: col('border'),
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: col('surface_variant'),
        circularTrackColor: col('surface_variant'),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: col('surface_variant'),
        contentTextStyle: TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: col('border')),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: col('surface_variant'),
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: col('border')),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: col('surface_variant'),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: col('border')),
        ),
        textStyle: TextStyle(color: textPrimary, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(col('accent').withValues(alpha: 0.5)),
        trackColor: WidgetStatePropertyAll(col('surface_variant')),
        thickness: const WidgetStatePropertyAll(4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent.withValues(alpha: 0.4)
              : null,
        ),
      ),
    ),
  );
}

class AppThemeData {
  final bool isDark;
  final Map<String, String> colors;
  final ThemeData theme;

  const AppThemeData({
    required this.isDark,
    required this.colors,
    required this.theme,
  });

  Color color(String key) =>
      Color(int.parse(colors[key]!.replaceFirst('#', '0xFF')));

  ThemeData dark() => buildAppTheme(mode: ThemeMode.dark).theme;
  ThemeData light() => buildAppTheme(mode: ThemeMode.light).theme;
}

/// Color de la paleta extendida ([AppColors]) según el brillo del tema actual.
/// Útil para `success`/`warning`/`info`/`error` que no tienen equivalente
/// directo en el [ColorScheme]. Equivale a `AppThemeData.color` pero para
/// widgets que no tienen el [AppThemeData] a mano.
Color appColor(BuildContext context, String key) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final hex = AppColors.of(isDark)[key]!;
  return Color(int.parse(hex.replaceFirst('#', '0xFF')));
}
