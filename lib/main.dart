import 'package:flutter/material.dart';
import 'package:production_planning/core/themes/theme.dart';
import 'package:production_planning/features/main_page/presentation/pages/main_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: lightTheme,
      home: MainPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
