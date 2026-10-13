import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.orange,
    required this.green,
    required this.blue,
    required this.purple,
    required this.red,
    required this.amber,
  });

  final Color orange;
  final Color green;
  final Color blue;
  final Color purple;
  final Color red;
  final Color amber;

  static const light = AppColors(
    orange: Color(0xFFFF6B35),
    green: Color(0xFF22B573),
    blue: Color(0xFF3B82F6),
    purple: Color(0xFF6C4DF0),
    red: Color(0xFFE5484D),
    amber: Color(0xFFF59E0B),
  );

  List<Color> get avatarAccents => [red, amber, purple, green, blue, orange];

  @override
  AppColors copyWith({
    Color? orange,
    Color? green,
    Color? blue,
    Color? purple,
    Color? red,
    Color? amber,
  }) {
    return AppColors(
      orange: orange ?? this.orange,
      green: green ?? this.green,
      blue: blue ?? this.blue,
      purple: purple ?? this.purple,
      red: red ?? this.red,
      amber: amber ?? this.amber,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      orange: Color.lerp(orange, other.orange, t)!,
      green: Color.lerp(green, other.green, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      red: Color.lerp(red, other.red, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

class AppTheme {
  const AppTheme._();

  static const _seed = Color(0xFF5B3FD9);
  static const _background = Color(0xFFF6F5FB);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: _seed).copyWith(
      primary: _seed,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: _background,
      extensions: const [AppColors.light],
      appBarTheme: AppBarTheme(
        backgroundColor: _background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 8,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow.withValues(alpha: 0.2),
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 26,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
    );
  }
}
