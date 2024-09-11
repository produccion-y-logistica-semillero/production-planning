import "package:flutter/material.dart";

class MaterialTheme {
  final TextTheme textTheme;

  const MaterialTheme(this.textTheme);

  static ColorScheme lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(4278609790),
      surfaceTint: Color(4278609790),
      onPrimary: Color(4294967295),
      primaryContainer: Color(4290177791),
      onPrimaryContainer: Color(4278198056),
      secondary: Color(4283196010),
      onSecondary: Color(4294967295),
      secondaryContainer: Color(4291815152),
      onSecondaryContainer: Color(4278656550),
      tertiary: Color(4284111998),
      onTertiary: Color(4294967295),
      tertiaryContainer: Color(4292927743),
      onTertiaryContainer: Color(4279638327),
      error: Color(4290386458),
      onError: Color(4294967295),
      errorContainer: Color(4294957782),
      onErrorContainer: Color(4282449922),
      surface: Color(4294310653),
      onSurface: Color(4279704607),
      onSurfaceVariant: Color(4282402892),
      outline: Color(4285560956),
      outlineVariant: Color(4290758860),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4281086260),
      inversePrimary: Color(4287091179),
      primaryFixed: Color(4290177791),
      onPrimaryFixed: Color(4278198056),
      primaryFixedDim: Color(4287091179),
      onPrimaryFixedVariant: Color(4278210144),
      secondaryFixed: Color(4291815152),
      onSecondaryFixed: Color(4278656550),
      secondaryFixedDim: Color(4289972948),
      onSecondaryFixedVariant: Color(4281616978),
      tertiaryFixed: Color(4292927743),
      onTertiaryFixed: Color(4279638327),
      tertiaryFixedDim: Color(4290954219),
      onTertiaryFixedVariant: Color(4282532965),
      surfaceDim: Color(4292271070),
      surfaceBright: Color(4294310653),
      surfaceContainerLowest: Color(4294967295),
      surfaceContainerLow: Color(4293915895),
      surfaceContainer: Color(4293586929),
      surfaceContainerHigh: Color(4293192172),
      surfaceContainerHighest: Color(4292797414),
    );
  }

  ThemeData light() {
    return theme(lightScheme());
  }

  static ColorScheme lightMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(4278208859),
      surfaceTint: Color(4278609790),
      onPrimary: Color(4294967295),
      primaryContainer: Color(4281237142),
      onPrimaryContainer: Color(4294967295),
      secondary: Color(4281353806),
      onSecondary: Color(4294967295),
      secondaryContainer: Color(4284643457),
      onSecondaryContainer: Color(4294967295),
      tertiary: Color(4282269793),
      onTertiary: Color(4294967295),
      tertiaryContainer: Color(4285559445),
      onTertiaryContainer: Color(4294967295),
      error: Color(4287365129),
      onError: Color(4294967295),
      errorContainer: Color(4292490286),
      onErrorContainer: Color(4294967295),
      surface: Color(4294310653),
      onSurface: Color(4279704607),
      onSurfaceVariant: Color(4282139720),
      outline: Color(4283981924),
      outlineVariant: Color(4285824128),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4281086260),
      inversePrimary: Color(4287091179),
      primaryFixed: Color(4281237142),
      onPrimaryFixed: Color(4294967295),
      primaryFixedDim: Color(4278215804),
      onPrimaryFixedVariant: Color(4294967295),
      secondaryFixed: Color(4284643457),
      onSecondaryFixed: Color(4294967295),
      secondaryFixedDim: Color(4282998632),
      onSecondaryFixedVariant: Color(4294967295),
      tertiaryFixed: Color(4285559445),
      onTertiaryFixed: Color(4294967295),
      tertiaryFixedDim: Color(4283914619),
      onTertiaryFixedVariant: Color(4294967295),
      surfaceDim: Color(4292271070),
      surfaceBright: Color(4294310653),
      surfaceContainerLowest: Color(4294967295),
      surfaceContainerLow: Color(4293915895),
      surfaceContainer: Color(4293586929),
      surfaceContainerHigh: Color(4293192172),
      surfaceContainerHighest: Color(4292797414),
    );
  }

  ThemeData lightMediumContrast() {
    return theme(lightMediumContrastScheme());
  }

  static ColorScheme lightHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(4278199857),
      surfaceTint: Color(4278609790),
      onPrimary: Color(4294967295),
      primaryContainer: Color(4278208859),
      onPrimaryContainer: Color(4294967295),
      secondary: Color(4279117101),
      onSecondary: Color(4294967295),
      secondaryContainer: Color(4281353806),
      onSecondaryContainer: Color(4294967295),
      tertiary: Color(4280098622),
      onTertiary: Color(4294967295),
      tertiaryContainer: Color(4282269793),
      onTertiaryContainer: Color(4294967295),
      error: Color(4283301890),
      onError: Color(4294967295),
      errorContainer: Color(4287365129),
      onErrorContainer: Color(4294967295),
      surface: Color(4294310653),
      onSurface: Color(4278190080),
      onSurfaceVariant: Color(4280100136),
      outline: Color(4282139720),
      outlineVariant: Color(4282139720),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4281086260),
      inversePrimary: Color(4291883519),
      primaryFixed: Color(4278208859),
      onPrimaryFixed: Color(4294967295),
      primaryFixedDim: Color(4278202686),
      onPrimaryFixedVariant: Color(4294967295),
      secondaryFixed: Color(4281353806),
      onSecondaryFixed: Color(4294967295),
      secondaryFixedDim: Color(4279906359),
      onSecondaryFixedVariant: Color(4294967295),
      tertiaryFixed: Color(4282269793),
      onTertiaryFixed: Color(4294967295),
      tertiaryFixedDim: Color(4280822345),
      onTertiaryFixedVariant: Color(4294967295),
      surfaceDim: Color(4292271070),
      surfaceBright: Color(4294310653),
      surfaceContainerLowest: Color(4294967295),
      surfaceContainerLow: Color(4293915895),
      surfaceContainer: Color(4293586929),
      surfaceContainerHigh: Color(4293192172),
      surfaceContainerHighest: Color(4292797414),
    );
  }

  ThemeData lightHighContrast() {
    return theme(lightHighContrastScheme());
  }

  static ColorScheme darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(4287091179),
      surfaceTint: Color(4287091179),
      onPrimary: Color(4278203715),
      primaryContainer: Color(4278210144),
      onPrimaryContainer: Color(4290177791),
      secondary: Color(4289972948),
      onSecondary: Color(4280169275),
      secondaryContainer: Color(4281616978),
      onSecondaryContainer: Color(4291815152),
      tertiary: Color(4290954219),
      onTertiary: Color(4281085517),
      tertiaryContainer: Color(4282532965),
      onTertiaryContainer: Color(4292927743),
      error: Color(4294948011),
      onError: Color(4285071365),
      errorContainer: Color(4287823882),
      onErrorContainer: Color(4294957782),
      surface: Color(4279178262),
      onSurface: Color(4292797414),
      onSurfaceVariant: Color(4290758860),
      outline: Color(4287271574),
      outlineVariant: Color(4282402892),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4292797414),
      inversePrimary: Color(4278609790),
      primaryFixed: Color(4290177791),
      onPrimaryFixed: Color(4278198056),
      primaryFixedDim: Color(4287091179),
      onPrimaryFixedVariant: Color(4278210144),
      secondaryFixed: Color(4291815152),
      onSecondaryFixed: Color(4278656550),
      secondaryFixedDim: Color(4289972948),
      onSecondaryFixedVariant: Color(4281616978),
      tertiaryFixed: Color(4292927743),
      onTertiaryFixed: Color(4279638327),
      tertiaryFixedDim: Color(4290954219),
      onTertiaryFixedVariant: Color(4282532965),
      surfaceDim: Color(4279178262),
      surfaceBright: Color(4281678396),
      surfaceContainerLowest: Color(4278849297),
      surfaceContainerLow: Color(4279704607),
      surfaceContainer: Color(4279967779),
      surfaceContainerHigh: Color(4280625965),
      surfaceContainerHighest: Color(4281349688),
    );
  }

  ThemeData dark() {
    return theme(darkScheme());
  }

  static ColorScheme darkMediumContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(4287419888),
      surfaceTint: Color(4287091179),
      onPrimary: Color(4278196513),
      primaryContainer: Color(4283407027),
      onPrimaryContainer: Color(4278190080),
      secondary: Color(4290236120),
      onSecondary: Color(4278327584),
      secondaryContainer: Color(4286485662),
      onSecondaryContainer: Color(4278190080),
      tertiary: Color(4291283183),
      onTertiary: Color(4279309105),
      tertiaryContainer: Color(4287401651),
      onTertiaryContainer: Color(4278190080),
      error: Color(4294949553),
      onError: Color(4281794561),
      errorContainer: Color(4294923337),
      onErrorContainer: Color(4278190080),
      surface: Color(4279178262),
      onSurface: Color(4294441982),
      onSurfaceVariant: Color(4291087568),
      outline: Color(4288455848),
      outlineVariant: Color(4286350472),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4292797414),
      inversePrimary: Color(4278210402),
      primaryFixed: Color(4290177791),
      onPrimaryFixed: Color(4278195226),
      primaryFixedDim: Color(4287091179),
      onPrimaryFixedVariant: Color(4278205515),
      secondaryFixed: Color(4291815152),
      onSecondaryFixed: Color(4278195226),
      secondaryFixedDim: Color(4289972948),
      onSecondaryFixedVariant: Color(4280564033),
      tertiaryFixed: Color(4292927743),
      onTertiaryFixed: Color(4278980140),
      tertiaryFixedDim: Color(4290954219),
      onTertiaryFixedVariant: Color(4281414483),
      surfaceDim: Color(4279178262),
      surfaceBright: Color(4281678396),
      surfaceContainerLowest: Color(4278849297),
      surfaceContainerLow: Color(4279704607),
      surfaceContainer: Color(4279967779),
      surfaceContainerHigh: Color(4280625965),
      surfaceContainerHighest: Color(4281349688),
    );
  }

  ThemeData darkMediumContrast() {
    return theme(darkMediumContrastScheme());
  }

  static ColorScheme darkHighContrastScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(4294376703),
      surfaceTint: Color(4287091179),
      onPrimary: Color(4278190080),
      primaryContainer: Color(4287419888),
      onPrimaryContainer: Color(4278190080),
      secondary: Color(4294376703),
      onSecondary: Color(4278190080),
      secondaryContainer: Color(4290236120),
      onSecondaryContainer: Color(4278190080),
      tertiary: Color(4294834687),
      onTertiary: Color(4278190080),
      tertiaryContainer: Color(4291283183),
      onTertiaryContainer: Color(4278190080),
      error: Color(4294965753),
      onError: Color(4278190080),
      errorContainer: Color(4294949553),
      onErrorContainer: Color(4278190080),
      surface: Color(4279178262),
      onSurface: Color(4294967295),
      onSurfaceVariant: Color(4294376703),
      outline: Color(4291087568),
      outlineVariant: Color(4291087568),
      shadow: Color(4278190080),
      scrim: Color(4278190080),
      inverseSurface: Color(4292797414),
      inversePrimary: Color(4278201915),
      primaryFixed: Color(4290965247),
      onPrimaryFixed: Color(4278190080),
      primaryFixedDim: Color(4287419888),
      onPrimaryFixedVariant: Color(4278196513),
      secondaryFixed: Color(4292078581),
      onSecondaryFixed: Color(4278190080),
      secondaryFixedDim: Color(4290236120),
      onSecondaryFixedVariant: Color(4278327584),
      tertiaryFixed: Color(4293256447),
      onTertiaryFixed: Color(4278190080),
      tertiaryFixedDim: Color(4291283183),
      onTertiaryFixedVariant: Color(4279309105),
      surfaceDim: Color(4279178262),
      surfaceBright: Color(4281678396),
      surfaceContainerLowest: Color(4278849297),
      surfaceContainerLow: Color(4279704607),
      surfaceContainer: Color(4279967779),
      surfaceContainerHigh: Color(4280625965),
      surfaceContainerHighest: Color(4281349688),
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
     scaffoldBackgroundColor: colorScheme.background,
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
