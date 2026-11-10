// lib/shared/workspace/workspace_session.dart
//
// The live workspace: which one is open, switching to another one without
// restarting the app, and the shift / time format that come with it.
//
// Switching reopens every dependency on the new database and bumps
// [appSession], so MyApp rebuilds its home with a new key and every page
// reloads from the new data (the same mechanism the guided tutorial uses).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:production_planning/core/data/db/sqllite_database_provider.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/shared/duration_input.dart';
import 'package:production_planning/shared/workspace/workspace_settings.dart';
import 'package:production_planning/shared/workspace/workspace_store.dart';

/// Bumped every time the workspace changes: MyApp rebuilds its home with a
/// new key, so every page reloads from the new database.
final ValueNotifier<int> appSession = ValueNotifier(0);

/// True while the dependencies are being reopened (MyApp shows a loader).
final ValueNotifier<bool> appSwitching = ValueNotifier(false);

/// Name of the workspace whose database is open right now (it is
/// "Tutorial" while the guided tour runs).
final ValueNotifier<String> openWorkspaceName =
    ValueNotifier(kDefaultWorkspace);

/// The store on the app-support folder.
Future<WorkspaceStore> appWorkspaceStore() async {
  final dir = await getApplicationSupportDirectory();
  return WorkspaceStore(dir.path);
}

/// Loads the shift and time format of the open workspace into the app.
/// A workspace without them takes the ones currently in memory.
Future<void> applyOpenWorkspacePreferences() async {
  final db = SQLLiteDatabaseProvider.current;
  if (db == null) return;
  final prefs = await loadPreferences(
    db,
    WorkspacePreferences(START_SCHEDULE, END_SCHEDULE, timeInputFormat.value),
  );
  START_SCHEDULE = prefs.start;
  END_SCHEDULE = prefs.end;
  timeInputFormat.value = prefs.format;
}

/// Opens [workspace] in place of the current one, without a restart.
/// [fresh] deletes its database first (used by the tutorial).
Future<void> reopenWorkspace(String workspace, {bool fresh = false}) async {
  appSwitching.value = true;
  try {
    // Let the old pages go away before their dependencies do.
    await WidgetsBinding.instance.endOfFrame;
    await depIn.reset();
    await SQLLiteDatabaseProvider.closeDatabaseConnection();
    if (fresh) await SQLLiteDatabaseProvider.deleteWorkspace(workspace);
    await initDependencies(workspace);
    openWorkspaceName.value = workspace;
    await applyOpenWorkspacePreferences();
  } finally {
    appSession.value++;
    appSwitching.value = false;
  }
}

/// Makes [workspace] the open one (now and at the next start).
Future<void> switchWorkspace(String workspace) async {
  final store = await appWorkspaceStore();
  await store.setCurrent(workspace);
  await reopenWorkspace(workspace);
}

/// Runs [action] with the open workspace's database closed (to rename or
/// replace its file) and opens [reopenAs] (default: the same one) after.
Future<T> withOpenWorkspaceClosed<T>(Future<T> Function() action,
    {String? reopenAs}) async {
  final current = openWorkspaceName.value;
  var done = false;
  appSwitching.value = true;
  try {
    await WidgetsBinding.instance.endOfFrame;
    await depIn.reset();
    await SQLLiteDatabaseProvider.closeDatabaseConnection();
    final result = await action();
    done = true;
    return result;
  } finally {
    // If the action failed, the old workspace is still where it was.
    final name = done ? (reopenAs ?? current) : current;
    await initDependencies(name);
    openWorkspaceName.value = name;
    await applyOpenWorkspacePreferences();
    appSession.value++;
    appSwitching.value = false;
  }
}

/// Saves the work shift in the open workspace.
Future<void> saveSchedule(TimeOfDay start, TimeOfDay end) async {
  START_SCHEDULE = start;
  END_SCHEDULE = end;
  final db = SQLLiteDatabaseProvider.current;
  if (db != null) {
    await writeSettings(db, {
      kSettingScheduleStart: timeOfDayToStorage(start),
      kSettingScheduleEnd: timeOfDayToStorage(end),
    });
  }
  if (openWorkspaceName.value == kTutorialWorkspaceName) return;
  // Also the starting point of workspaces that have no shift yet.
  final dir = await getApplicationSupportDirectory();
  await File('${dir.path}/schedule.txt').writeAsString(
      '${timeOfDayToStorage(start)}\n${timeOfDayToStorage(end)}');
}

/// Saves the time format in the open workspace.
Future<void> saveTimeFormat(TimeInputFormat format) async {
  timeInputFormat.value = format;
  final db = SQLLiteDatabaseProvider.current;
  if (db != null) {
    await writeSettings(db, {kSettingTimeFormat: timeFormatToStorage(format)});
  }
  if (openWorkspaceName.value == kTutorialWorkspaceName) return;
  final dir = await getApplicationSupportDirectory();
  await File('${dir.path}/$timeFormatFileName')
      .writeAsString(timeFormatToStorage(format));
}
