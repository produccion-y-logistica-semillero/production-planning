import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/core/themes/theme.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/main_page/presentation/pages/main_page.dart';

void main() async {
  await initDependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return  MaterialApp(
        title: 'Flutter Demo',
        theme: lightTheme,
        home: MainPage(),
        debugShowCheckedModeBanner: false,
    );
  }
}
