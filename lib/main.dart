import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/core/themes/theme.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/main_page/presentation/pages/main_page.dart';
import 'package:production_planning/features/main_page/presentation/provider/side_menu_provider.dart';
import 'package:provider/provider.dart';

void logMessage(String message) {
  final logFile = File('log.txt');
  logFile.writeAsStringSync(message + '\n', mode: FileMode.append);
}

void main() async {
  logMessage('App started');
  await initDependencies();
  logMessage('dependencies started');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return  MaterialApp(
        title: 'Flutter Demo',
        theme: lightTheme,
        //here we provide the provider of the side menu
        home: ChangeNotifierProvider(
          create: (context)=>SideMenuProvider(),
          child: MainPage()
        ),
        debugShowCheckedModeBanner: false,
    );
  }
}
