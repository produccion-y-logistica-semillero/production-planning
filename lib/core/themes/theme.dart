import "package:flutter/material.dart";

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static ColorScheme lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff06677e),
      surfaceTint: Color(0xff06677e),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffb6eaff),
      onPrimaryContainer: Color(0xff001f28),
      secondary: Color(0xff4c626a),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffcfe6f0),
      onSecondaryContainer: Color(0xff071e26),
      tertiary: Color(0xff5a5c7e),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xffe0e0ff),
      onTertiaryContainer: Color(0xff161937),
      error: Color(0xffba1a1a),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffffdad6),
      onErrorContainer: Color(0xff410002),
      surface: Color(0xfff5fafd),
      onSurface: Color(0xff171c1f),
      onSurfaceVariant: Color(0xff40484c),
      outline: Color(0xff70787c),
      outlineVariant: Color(0xffbfc8cc),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff2c3134),
      inversePrimary: Color(0xff87d1eb),
      primaryFixed: Color(0xffb6eaff),
      onPrimaryFixed: Color(0xff001f28),
      primaryFixedDim: Color(0xff87d1eb),
      onPrimaryFixedVariant: Color(0xff004e60),
      secondaryFixed: Color(0xffcfe6f0),
      onSecondaryFixed: Color(0xff071e26),
      secondaryFixedDim: Color(0xffb3cad4),
      onSecondaryFixedVariant: Color(0xff344a52),
      tertiaryFixed: Color(0xffe0e0ff),
      onTertiaryFixed: Color(0xff161937),
      tertiaryFixedDim: Color(0xffc2c3eb),
      onTertiaryFixedVariant: Color(0xff424465),
      surfaceDim: Color(0xffd6dbde),
      surfaceBright: Color(0xfff5fafd),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xffeff4f7),
      surfaceContainer: Color(0xffeaeff1),
      surfaceContainerHigh: Color(0xffe4e9ec),
      surfaceContainerHighest: Color(0xffdee3e6),
    );
  }

  ThemeData light() {
    return theme(lightScheme());
  }

  static ColorScheme lightMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff00495b),
      surfaceTint: Color(0xff06677e),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xff2e7e96),
      onPrimaryContainer: Color(0xffffffff),
      secondary: Color(0xff30464e),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xff627881),
      onSecondaryContainer: Color(0xffffffff),
      tertiary: Color(0xff3e4061),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xff707295),
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff8c0009),
      onError: Color(0xffffffff),
      errorContainer: Color(0xffda342e),
      onErrorContainer: Color(0xffffffff),
      surface: Color(0xfff5fafd),
      onSurface: Color(0xff171c1f),
      onSurfaceVariant: Color(0xff3c4448),
      outline: Color(0xff586064),
      outlineVariant: Color(0xff747c80),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff2c3134),
      inversePrimary: Color(0xff87d1eb),
      primaryFixed: Color(0xff2e7e96),
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: Color(0xff00647c),
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: Color(0xff627881),
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: Color(0xff495f68),
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: Color(0xff707295),
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: Color(0xff57597b),
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: Color(0xffd6dbde),
      surfaceBright: Color(0xfff5fafd),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xffeff4f7),
      surfaceContainer: Color(0xffeaeff1),
      surfaceContainerHigh: Color(0xffe4e9ec),
      surfaceContainerHighest: Color(0xffdee3e6),
    );
  }

  ThemeData lightMediumContrast() {
    return theme(lightMediumContrastScheme());
  }

  static ColorScheme lightHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff002631),
      surfaceTint: Color(0xff06677e),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xff00495b),
      onPrimaryContainer: Color(0xffffffff),
      secondary: Color(0xff0e252d),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xff30464e),
      onSecondaryContainer: Color(0xffffffff),
      tertiary: Color(0xff1d1f3e),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xff3e4061),
      onTertiaryContainer: Color(0xffffffff),
      error: Color(0xff4e0002),
      onError: Color(0xffffffff),
      errorContainer: Color(0xff8c0009),
      onErrorContainer: Color(0xffffffff),
      surface: Color(0xfff5fafd),
      onSurface: Color(0xff000000),
      onSurfaceVariant: Color(0xff1d2528),
      outline: Color(0xff3c4448),
      outlineVariant: Color(0xff3c4448),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xff2c3134),
      inversePrimary: Color(0xffd0f1ff),
      primaryFixed: Color(0xff00495b),
      onPrimaryFixed: Color(0xffffffff),
      primaryFixedDim: Color(0xff00313e),
      onPrimaryFixedVariant: Color(0xffffffff),
      secondaryFixed: Color(0xff30464e),
      onSecondaryFixed: Color(0xffffffff),
      secondaryFixedDim: Color(0xff1a3037),
      onSecondaryFixedVariant: Color(0xffffffff),
      tertiaryFixed: Color(0xff3e4061),
      onTertiaryFixed: Color(0xffffffff),
      tertiaryFixedDim: Color(0xff282a49),
      onTertiaryFixedVariant: Color(0xffffffff),
      surfaceDim: Color(0xffd6dbde),
      surfaceBright: Color(0xfff5fafd),
      surfaceContainerLowest: Color(0xffffffff),
      surfaceContainerLow: Color(0xffeff4f7),
      surfaceContainer: Color(0xffeaeff1),
      surfaceContainerHigh: Color(0xffe4e9ec),
      surfaceContainerHighest: Color(0xffdee3e6),
    );
  }

  ThemeData lightHighContrast() {
    return theme(lightHighContrastScheme());
  }

  static ColorScheme darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xff87d1eb),
      surfaceTint: Color(0xff87d1eb),
      onPrimary: Color(0xff003543),
      primaryContainer: Color(0xff004e60),
      onPrimaryContainer: Color(0xffb6eaff),
      secondary: Color(0xffb3cad4),
      onSecondary: Color(0xff1e333b),
      secondaryContainer: Color(0xff344a52),
      onSecondaryContainer: Color(0xffcfe6f0),
      tertiary: Color(0xffc2c3eb),
      onTertiary: Color(0xff2c2e4d),
      tertiaryContainer: Color(0xff424465),
      onTertiaryContainer: Color(0xffe0e0ff),
      error: Color(0xffffb4ab),
      onError: Color(0xff690005),
      errorContainer: Color(0xff93000a),
      onErrorContainer: Color(0xffffdad6),
      surface: Color(0xff0f1416),
      onSurface: Color(0xffdee3e6),
      onSurfaceVariant: Color(0xffbfc8cc),
      outline: Color(0xff8a9296),
      outlineVariant: Color(0xff40484c),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffdee3e6),
      inversePrimary: Color(0xff06677e),
      primaryFixed: Color(0xffb6eaff),
      onPrimaryFixed: Color(0xff001f28),
      primaryFixedDim: Color(0xff87d1eb),
      onPrimaryFixedVariant: Color(0xff004e60),
      secondaryFixed: Color(0xffcfe6f0),
      onSecondaryFixed: Color(0xff071e26),
      secondaryFixedDim: Color(0xffb3cad4),
      onSecondaryFixedVariant: Color(0xff344a52),
      tertiaryFixed: Color(0xffe0e0ff),
      onTertiaryFixed: Color(0xff161937),
      tertiaryFixedDim: Color(0xffc2c3eb),
      onTertiaryFixedVariant: Color(0xff424465),
      surfaceDim: Color(0xff0f1416),
      surfaceBright: Color(0xff353a3c),
      surfaceContainerLowest: Color(0xff0a0f11),
      surfaceContainerLow: Color(0xff171c1f),
      surfaceContainer: Color(0xff1b2023),
      surfaceContainerHigh: Color(0xff252b2d),
      surfaceContainerHighest: Color(0xff303638),
    );
  }

  ThemeData dark() {
    return theme(darkScheme());
  }

  static ColorScheme darkMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xff8cd5f0),
      surfaceTint: Color(0xff87d1eb),
      onPrimary: Color(0xff001921),
      primaryContainer: Color(0xff4f9ab3),
      onPrimaryContainer: Color(0xff000000),
      secondary: Color(0xffb7ced8),
      onSecondary: Color(0xff021920),
      secondaryContainer: Color(0xff7e949e),
      onSecondaryContainer: Color(0xff000000),
      tertiary: Color(0xffc7c8ef),
      onTertiary: Color(0xff111331),
      tertiaryContainer: Color(0xff8c8eb3),
      onTertiaryContainer: Color(0xff000000),
      error: Color(0xffffbab1),
      onError: Color(0xff370001),
      errorContainer: Color(0xffff5449),
      onErrorContainer: Color(0xff000000),
      surface: Color(0xff0f1416),
      onSurface: Color(0xfff7fbfe),
      onSurfaceVariant: Color(0xffc4ccd0),
      outline: Color(0xff9ca4a8),
      outlineVariant: Color(0xff7c8488),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffdee3e6),
      inversePrimary: Color(0xff004f62),
      primaryFixed: Color(0xffb6eaff),
      onPrimaryFixed: Color(0xff00141a),
      primaryFixedDim: Color(0xff87d1eb),
      onPrimaryFixedVariant: Color(0xff003c4b),
      secondaryFixed: Color(0xffcfe6f0),
      onSecondaryFixed: Color(0xff00141a),
      secondaryFixedDim: Color(0xffb3cad4),
      onSecondaryFixedVariant: Color(0xff243941),
      tertiaryFixed: Color(0xffe0e0ff),
      onTertiaryFixed: Color(0xff0c0e2c),
      tertiaryFixedDim: Color(0xffc2c3eb),
      onTertiaryFixedVariant: Color(0xff313353),
      surfaceDim: Color(0xff0f1416),
      surfaceBright: Color(0xff353a3c),
      surfaceContainerLowest: Color(0xff0a0f11),
      surfaceContainerLow: Color(0xff171c1f),
      surfaceContainer: Color(0xff1b2023),
      surfaceContainerHigh: Color(0xff252b2d),
      surfaceContainerHighest: Color(0xff303638),
    );
  }

  ThemeData darkMediumContrast() {
    return theme(darkMediumContrastScheme());
  }

  static ColorScheme darkHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xfff6fcff),
      surfaceTint: Color(0xff87d1eb),
      onPrimary: Color(0xff000000),
      primaryContainer: Color(0xff8cd5f0),
      onPrimaryContainer: Color(0xff000000),
      secondary: Color(0xfff6fcff),
      onSecondary: Color(0xff000000),
      secondaryContainer: Color(0xffb7ced8),
      onSecondaryContainer: Color(0xff000000),
      tertiary: Color(0xfffdf9ff),
      onTertiary: Color(0xff000000),
      tertiaryContainer: Color(0xffc7c8ef),
      onTertiaryContainer: Color(0xff000000),
      error: Color(0xfffff9f9),
      onError: Color(0xff000000),
      errorContainer: Color(0xffffbab1),
      onErrorContainer: Color(0xff000000),
      surface: Color(0xff0f1416),
      onSurface: Color(0xffffffff),
      onSurfaceVariant: Color(0xfff6fcff),
      outline: Color(0xffc4ccd0),
      outlineVariant: Color(0xffc4ccd0),
      shadow: Color(0xff000000),
      scrim: Color(0xff000000),
      inverseSurface: Color(0xffdee3e6),
      inversePrimary: Color(0xff002e3b),
      primaryFixed: Color(0xffc2eeff),
      onPrimaryFixed: Color(0xff000000),
      primaryFixedDim: Color(0xff8cd5f0),
      onPrimaryFixedVariant: Color(0xff001921),
      secondaryFixed: Color(0xffd3ebf5),
      onSecondaryFixed: Color(0xff000000),
      secondaryFixedDim: Color(0xffb7ced8),
      onSecondaryFixedVariant: Color(0xff021920),
      tertiaryFixed: Color(0xffe5e4ff),
      onTertiaryFixed: Color(0xff000000),
      tertiaryFixedDim: Color(0xffc7c8ef),
      onTertiaryFixedVariant: Color(0xff111331),
      surfaceDim: Color(0xff0f1416),
      surfaceBright: Color(0xff353a3c),
      surfaceContainerLowest: Color(0xff0a0f11),
      surfaceContainerLow: Color(0xff171c1f),
      surfaceContainer: Color(0xff1b2023),
      surfaceContainerHigh: Color(0xff252b2d),
      surfaceContainerHighest: Color(0xff303638),
    );
  }

  ThemeData darkHighContrast() {
    return theme(darkHighContrastScheme());
  }


  ThemeData theme(ColorScheme colorScheme) => ThemeData(
     useMaterial3: true,
     brightness: colorScheme.brightness,
     colorScheme: colorScheme,
     textTheme: textTheme.apply(
       bodyColor: colorScheme.onSurface,
       displayColor: colorScheme.onSurface,
     ),
     scaffoldBackgroundColor: colorScheme.surface,
     canvasColor: colorScheme.surface,
  );


  List<ExtendedColor> get extendedColors => [
  ];
}

class ExtendedColor {
  final Color seed, value;
  final ColorFamily light;
  final ColorFamily lightHighContrast;
  final ColorFamily lightMediumContrast;
  final ColorFamily dark;
  final ColorFamily darkHighContrast;
  final ColorFamily darkMediumContrast;

  const ExtendedColor({
    required this.seed,
    required this.value,
    required this.light,
    required this.lightHighContrast,
    required this.lightMediumContrast,
    required this.dark,
    required this.darkHighContrast,
    required this.darkMediumContrast,
  });
}

class ColorFamily {
  const ColorFamily({
    required this.color,
    required this.onColor,
    required this.colorContainer,
    required this.onColorContainer,
  });

  final Color color;
  final Color onColor;
  final Color colorContainer;
  final Color onColorContainer;
}
