import 'package:production_planning/shared/notation.dart';
import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/presentation/main_page/presentation/pages/main_page.dart';
import 'package:production_planning/presentation/main_page/presentation/provider/side_menu_provider.dart';
import 'package:production_planning/shared/duration_input.dart';
import 'package:production_planning/shared/motion/motion.dart';
import 'package:production_planning/shared/tutorial/tutorial_layer.dart';
import 'package:production_planning/shared/tutorial/tutorial_workspace.dart';
import 'package:production_planning/shared/workspace/workspace_session.dart'
    show applyOpenWorkspacePreferences, openWorkspaceName;
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);

  String workspace = 'default';
  final workspaceFile = File('${dir.path}/workspace.txt');
  if (await workspaceFile.exists()) {
    workspace = await workspaceFile
        .readAsLines()
        .then((lines) => lines.isNotEmpty ? lines[0] : 'default');
  } else {
    await workspaceFile.writeAsString('default');
  }

  final scheduleFile = File('${dir.path}/schedule.txt');

  if (await scheduleFile.exists()) {
    final lines = await scheduleFile.readAsLines();
    if (lines.length >= 2) {
      START_SCHEDULE = _parseTimeOfDay(lines[0]) ?? START_SCHEDULE;
      END_SCHEDULE = _parseTimeOfDay(lines[1]) ?? END_SCHEDULE;
    }
  } else {
    await scheduleFile.writeAsString('08:00\n16:00');
  }

  final notationFile = File('${dir.path}/$notationFileName');
  if (await notationFile.exists()) {
    showNotation.value = (await notationFile.readAsString()).trim() == '1';
  }

  // Format of every duration field: hh:mm:ss or minutes ("Formato de tiempos").
  final timeFormatFile = File('${dir.path}/$timeFormatFileName');
  if (await timeFormatFile.exists()) {
    timeInputFormat.value =
        timeFormatFromStorage(await timeFormatFile.readAsString());
  }

  await initDependencies(workspace);
  openWorkspaceName.value = workspace;
  // The shift and the time format belong to the workspace (they travel
  // with it to another computer); the files above are only the starting
  // point of a workspace that has none yet.
  await applyOpenWorkspacePreferences();
  runApp(const MyApp());
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
      title: 'Programación de Operaciones',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey,
            brightness: Brightness.light,
            dynamicSchemeVariant: DynamicSchemeVariant.content),
        // textTheme: GoogleFonts.lexendDecaTextTheme()
        // Every page (side menu and pushed screens) fades in rising a bit.
        pageTransitionsTheme: kAppPageTransitions,
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 400),
          showDuration: Duration(seconds: 3),
        ),
      ),
      // The guided tutorial is drawn above every route and dialog.
      builder: (context, child) => TutorialLayer(child: child!),
      // A new key per workspace session: switching to or from the tutorial
      // workspace rebuilds every page from the new database.
      home: ValueListenableBuilder<bool>(
        valueListenable: appSwitching,
        builder: (context, switching, _) => switching
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : ValueListenableBuilder<int>(
                valueListenable: appSession,
                builder: (context, session, _) => ChangeNotifierProvider(
                  key: ValueKey(session),
                  create: (context) => SideMenuProvider(),
                  child: MainPage(),
                ),
              ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
