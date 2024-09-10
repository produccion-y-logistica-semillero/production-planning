import 'package:flutter/material.dart';

final ThemeData lightTheme = ThemeData(
  brightness:  Brightness.light,
  colorScheme: const ColorScheme.light(
    surface:  Color.fromARGB(255, 239, 249, 255),
    //primary: (Color.fromARGB(255, 150, 164, 239))!,
   // onPrimary:  Colors.white,
    primaryContainer: Color.fromARGB(255, 44, 93, 199),
    onPrimaryContainer: Color.fromARGB(255, 255, 255, 255),
    secondaryContainer:  Color.fromARGB(255, 197, 202, 214),
    onSecondaryContainer: Color.fromARGB(255, 130, 136, 148),
    
  ),
  useMaterial3: true,   //We can check how it changes with this
);