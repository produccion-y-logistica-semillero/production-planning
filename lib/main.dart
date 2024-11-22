import 'package:flutter/material.dart';
import 'package:production_planning/core/themes/theme.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/features/main_page/presentation/pages/main_page.dart';
import 'package:production_planning/features/main_page/presentation/provider/side_menu_provider.dart';
import 'package:provider/provider.dart';
import 'dart:io';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String workspace = 'default';
  final workspaceFile = File('workspace.txt');
  if (await workspaceFile.exists()) {
    workspace = await workspaceFile.readAsLines().then((lines) => lines.isNotEmpty ? lines[0] : 'default');
  } else {
    await workspaceFile.writeAsString('default');
  }


  final scheduleFile = File('schedule.txt');

  if (await scheduleFile.exists()) {
    final lines = await scheduleFile.readAsLines();
    if (lines.length >= 2) {
      START_SCHEDULE = _parseTimeOfDay(lines[0]) ?? START_SCHEDULE;
      END_SCHEDULE = _parseTimeOfDay(lines[1]) ?? END_SCHEDULE;
    }
  } else {
    await scheduleFile.writeAsString('08:00\n16:00');
  }

  await initDependencies(workspace);
  runApp(MyApp());
}

TimeOfDay? _parseTimeOfDay(String time) {
  final parts = time.split(':');
  if (parts.length == 2) {
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour != null && minute != null) {
      return TimeOfDay(hour: hour, minute: minute);
    }
  }
  return null;
}

class MyApp extends StatelessWidget {

  const MyApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Planificación de la Producción',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: MaterialTheme.lightMediumContrastScheme(),
      ),
      home: ChangeNotifierProvider(
        create: (context) => SideMenuProvider(),
        child: MainPage(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
