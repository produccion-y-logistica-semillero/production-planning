import 'package:flutter/material.dart';

final ThemeData lightTheme = ThemeData(
  brightness:  Brightness.light,
  colorScheme: ColorScheme.light(
    surface: Color.fromARGB(255, 239, 249, 255),
    primary: (Colors.blue[100])!,
    primaryContainer: Color.fromARGB(255, 49, 103, 165),
    onPrimaryContainer: Colors.white,
    
  ),
  useMaterial3: true,   //We can check how it changes with this
);