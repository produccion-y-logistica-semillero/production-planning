// lib/shared/workspace/workspace_settings.dart
//
// Settings that belong to a workspace, not to the computer: the work shift
// (Horario) and the time format. They live in the workspace_settings table
// of the workspace database, so they travel inside an exported .ppws file
// and the same program gives the same schedule on any computer.
//
// The legacy files schedule.txt and time_format.txt are still read at
// start-up: a workspace opened for the first time (with no settings yet)
// takes whatever is in memory at that moment, i.e. those files or the
// workspace that was open before.
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'package:production_planning/shared/duration_input.dart';

const String kSettingScheduleStart = 'schedule_start';
const String kSettingScheduleEnd = 'schedule_end';
const String kSettingTimeFormat = 'time_format';
const String kSettingExportedAt = 'exported_at';
const String kSettingExportedFrom = 'exported_from';
const String kSettingWorkspaceName = 'workspace_name';

const String kWorkspaceSettingsTable = 'workspace_settings';

/// [time] as HH:mm.
String timeOfDayToStorage(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// "HH:mm" as a time, or null when it is not a valid clock time.
TimeOfDay? timeOfDayFromStorage(String? text) {
  if (text == null) return null;
  final parts = text.trim().split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return TimeOfDay(hour: h, minute: m);
}

Future<void> ensureSettingsTable(DatabaseExecutor db) => db.execute(
    'CREATE TABLE IF NOT EXISTS $kWorkspaceSettingsTable ('
    'key TEXT PRIMARY KEY, value TEXT NOT NULL)');

/// Every setting stored in [db] (empty when the table does not exist).
Future<Map<String, String>> readSettings(DatabaseExecutor db) async {
  final exists = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [kWorkspaceSettingsTable]);
  if (exists.isEmpty) return {};
  final rows = await db.query(kWorkspaceSettingsTable);
  return {
    for (final r in rows) r['key'] as String: (r['value'] ?? '').toString(),
  };
}

Future<void> writeSettings(
    DatabaseExecutor db, Map<String, String> values) async {
  await ensureSettingsTable(db);
  for (final e in values.entries) {
    await db.insert(
      kWorkspaceSettingsTable,
      {'key': e.key, 'value': e.value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

/// The shift and time format of one workspace.
class WorkspacePreferences {
  final TimeOfDay start;
  final TimeOfDay end;
  final TimeInputFormat format;

  const WorkspacePreferences(this.start, this.end, this.format);

  Map<String, String> toSettings() => {
        kSettingScheduleStart: timeOfDayToStorage(start),
        kSettingScheduleEnd: timeOfDayToStorage(end),
        kSettingTimeFormat: timeFormatToStorage(format),
      };
}

/// Reads the shift and time format of [db]. Values missing from the
/// database are filled from [fallback] and written back, so a workspace
/// created before this table existed keeps the settings the user had.
Future<WorkspacePreferences> loadPreferences(
    Database db, WorkspacePreferences fallback) async {
  final s = await readSettings(db);
  final start = timeOfDayFromStorage(s[kSettingScheduleStart]);
  final end = timeOfDayFromStorage(s[kSettingScheduleEnd]);
  final hasFormat = s.containsKey(kSettingTimeFormat);
  final prefs = WorkspacePreferences(
    start ?? fallback.start,
    end ?? fallback.end,
    hasFormat ? timeFormatFromStorage(s[kSettingTimeFormat]) : fallback.format,
  );
  if (start == null || end == null || !hasFormat) {
    await writeSettings(db, prefs.toSettings());
  }
  return prefs;
}
