import 'package:material_ui/material_ui.dart';

/// Colours that aren't part of Material's ColorScheme (gains, losses, warnings)
/// and differ between dark and light.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.gain,
    required this.loss,
    required this.warning,
    required this.muted,
    required this.hero,
    required this.heroText,
    required this.heroMuted,
    required this.divider,
  });

  final Color gain;
  final Color loss;
  final Color warning;

  /// Secondary text.
  final Color muted;

  /// The big portfolio card.
  final Color hero;
  final Color heroText;
  final Color heroMuted;
  final Color divider;

  static const dark = AppColors(
    gain: Color(0xFF5FD49B),
    loss: Color(0xFFFF8A80),
    warning: Color(0xFFF2C46D),
    muted: Color(0xFF9AA7C0),
    hero: Color(0xFF16254A),
    heroText: Color(0xFFF3F5FA),
    heroMuted: Color(0xFFAAB6CF),
    divider: Color(0xFF223154),
  );

  static const light = AppColors(
    gain: Color(0xFF15803D),
    loss: Color(0xFFB42318),
    warning: Color(0xFFA15C07),
    muted: Color(0xFF55607A),
    hero: Color(0xFF0E1A36),
    heroText: Color(0xFFF3F5FA),
    heroMuted: Color(0xFFB6C0D6),
    divider: Color(0xFFE2E6EE),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

class AppTheme {
  const AppTheme._();

  static const fontFamily = 'Manrope';

  // Deep navy palette with a champagne-gold accent.
  static const _navy950 = Color(0xFF070D1C);
  static const _navy900 = Color(0xFF0B1428);
  static const _navy850 = Color(0xFF101B34);
  static const _navy800 = Color(0xFF15223F);
  static const _navy700 = Color(0xFF223154);
  static const _gold = Color(0xFFD9B871);
  static const _goldDeep = Color(0xFF8C6A22);
  static const _ice = Color(0xFFE8ECF5);

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _gold,
      onPrimary: Color(0xFF231A05),
      primaryContainer: Color(0xFF3A2F14),
      onPrimaryContainer: Color(0xFFF5E3B8),
      secondary: Color(0xFF8FB0FF),
      onSecondary: Color(0xFF0A1633),
      secondaryContainer: Color(0xFF1E2F57),
      onSecondaryContainer: Color(0xFFD9E3FF),
      tertiary: Color(0xFF7FD8C4),
      onTertiary: Color(0xFF00201A),
      error: Color(0xFFFF8A80),
      onError: Color(0xFF3B0A06),
      surface: _navy900,
      onSurface: _ice,
      onSurfaceVariant: Color(0xFF9AA7C0),
      surfaceContainerLowest: _navy950,
      surfaceContainerLow: _navy850,
      surfaceContainer: _navy850,
      surfaceContainerHigh: _navy800,
      surfaceContainerHighest: Color(0xFF1B2A4C),
      outline: Color(0xFF34466F),
      outlineVariant: _navy700,
      inverseSurface: _ice,
      onInverseSurface: _navy900,
      inversePrimary: _goldDeep,
    );
    return _build(scheme, AppColors.dark);
  }

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1E3A7A),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCE4F7),
      onPrimaryContainer: Color(0xFF0B1A3D),
      secondary: _goldDeep,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFF4E8CC),
      onSecondaryContainer: Color(0xFF2E2205),
      tertiary: Color(0xFF0F766E),
      onTertiary: Colors.white,
      error: Color(0xFFB42318),
      onError: Colors.white,
      surface: Color(0xFFF5F6FA),
      onSurface: Color(0xFF0E1A36),
      onSurfaceVariant: Color(0xFF55607A),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: Color(0xFFEEF1F6),
      surfaceContainerHighest: Color(0xFFE6EAF2),
      outline: Color(0xFFBFC6D4),
      outlineVariant: Color(0xFFE2E6EE),
      inverseSurface: Color(0xFF0E1A36),
      onInverseSurface: Colors.white,
      inversePrimary: _gold,
    );
    return _build(scheme, AppColors.light);
  }

  static ThemeData _build(ColorScheme scheme, AppColors colors) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      // Manrope has no ₹ sign; Roboto (built into Android) supplies it.
      fontFamilyFallback: const ['Roboto'],
      scaffoldBackgroundColor: scheme.surface,
      extensions: [colors],
    );
    final text = base.textTheme;
    const tabular = [FontFeature.tabularFigures()];
    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
          fontFeatures: tabular,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          fontFeatures: tabular,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: tabular,
        ),
        titleSmall: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: tabular,
        ),
        bodyLarge: text.bodyLarge?.copyWith(fontFeatures: tabular),
        bodyMedium: text.bodyMedium?.copyWith(fontFeatures: tabular),
        bodySmall: text.bodySmall?.copyWith(
          color: colors.muted,
          fontFeatures: tabular,
        ),
        labelSmall: text.labelSmall?.copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: colors.muted,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: const ['Roboto'],
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        space: 1,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: s.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
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
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
    );
  }
}
