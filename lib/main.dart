import 'package:flutter/material.dart';
import 'package:production_planning/core/themes/theme.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/features/main_page/presentation/pages/main_page.dart';
import 'package:production_planning/features/main_page/presentation/provider/side_menu_provider.dart';
import 'package:provider/provider.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String workspace = 'default';
  final file = File('workspace.txt');
  if (await file.exists()) {
    workspace = await file.readAsLines().then((lines) => lines.isNotEmpty ? lines[0] : 'default');
  } else {
    await file.writeAsString('default');
  }

  await initDependencies(workspace);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return  MaterialApp(
        title: 'Planificacion de la produccion',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: MaterialTheme.lightMediumContrastScheme()
        ),
        //here we provide the provider of the side menu
        home: ChangeNotifierProvider(
          create: (context)=>SideMenuProvider(),
          child: MainPage()
        ),
        debugShowCheckedModeBanner: false,
    );
  }
}
