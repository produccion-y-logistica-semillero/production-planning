// lib/shared/tutorial/tutorial_workspace.dart
//
// The guided tutorial works in its own workspace ("Tutorial"), so what the
// user creates while learning never mixes with their real data. Entering
// it reopens the app's dependencies on a fresh Tutorial database without a
// restart; leaving it reopens the user's workspace. workspace.txt is not
// touched, so a restart always comes back to the user's own workspace.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:production_planning/core/data/db/sqllite_database_provider.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/shared/duration_input.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';

const String kTutorialWorkspace = 'Tutorial';

/// Bumped every time the workspace changes: MyApp rebuilds its home with a
/// new key, so every page reloads from the new database.
final ValueNotifier<int> appSession = ValueNotifier(0);

/// True while the dependencies are being reopened (MyApp shows a loader).
final ValueNotifier<bool> appSwitching = ValueNotifier(false);

String? _returnWorkspace;
TimeInputFormat? _returnTimeFormat;

/// True while the tutorial workspace is open.
bool get inTutorialWorkspace => _returnWorkspace != null;

Future<String> _currentWorkspace() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/workspace.txt');
  if (!await file.exists()) return 'default';
  final lines = await file.readAsLines();
  return lines.isNotEmpty && lines.first.trim().isNotEmpty
      ? lines.first.trim()
      : 'default';
}

Future<void> _openWorkspace(String workspace, {bool fresh = false}) async {
  appSwitching.value = true;
  // Let the old pages go away before their dependencies do.
  await WidgetsBinding.instance.endOfFrame;
  await depIn.reset();
  await SQLLiteDatabaseProvider.closeDatabaseConnection();
  if (fresh) await SQLLiteDatabaseProvider.deleteWorkspace(workspace);
  await initDependencies(workspace);
  appSession.value++;
  appSwitching.value = false;
}

/// Opens a clean tutorial workspace and starts [tour] in it. When the tour
/// ends (finished or abandoned) the user's workspace comes back.
Future<void> startGuidedTour(TutorialTour tour) async {
  if (!inTutorialWorkspace) {
    _returnWorkspace = await _currentWorkspace();
    _returnTimeFormat = timeInputFormat.value;
  }
  // The tour asks for durations in minutes ("escribe 30").
  timeInputFormat.value = TimeInputFormat.minutes;
  await _openWorkspace(kTutorialWorkspace, fresh: true);
  tutorial.onEnd = (_) => leaveTutorialWorkspace();
  tutorial.start(tour);
}

/// Back to the workspace that was open before the tutorial.
Future<void> leaveTutorialWorkspace() async {
  final back = _returnWorkspace;
  if (back == null) return;
  _returnWorkspace = null;
  if (_returnTimeFormat != null) timeInputFormat.value = _returnTimeFormat!;
  await _openWorkspace(back);
}
