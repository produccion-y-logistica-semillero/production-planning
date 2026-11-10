// lib/shared/workspace/workspace_store.dart
//
// Workspaces on disk. Each workspace is one SQLite file named
// "<name without spaces>_v3.db" in the app-support folder; workspace.txt
// keeps the open one on its first line and the display names after it.
//
// The store lists, creates, renames, duplicates and deletes workspaces and
// moves them between computers: export writes a self-contained copy
// (.ppws, a plain SQLite file with its shift and time format inside) and
// import validates such a file and copies it into the app-support folder.
// The copy there is the official one: the file the user picked (Downloads,
// a USB stick...) is never opened for writing.
//
// Pure file logic with no Flutter state, so it can be tested on a temporary
// folder. Opening, closing and switching the live workspace is done by
// workspace_session.dart.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:production_planning/core/data/db/sqllite_database_provider.dart';
import 'package:production_planning/shared/workspace/workspace_settings.dart';

const String kDefaultWorkspace = 'default';
const String kTutorialWorkspaceName = 'Tutorial';
const String kWorkspaceExtension = 'ppws';
const int kMaxWorkspaceNameLength = 40;

/// Tables every workspace has; a file without them is not a workspace.
const List<String> kCoreTables = [
  'machines',
  'sequences',
  'tasks',
  'orders',
  'jobs',
];

/// A problem the user must read (shown as is in the interface).
class WorkspaceException implements Exception {
  final String message;
  const WorkspaceException(this.message);
  @override
  String toString() => message;
}

class WorkspaceInfo {
  final String name;
  final String path;

  /// Null while the workspace was created but never opened (no file yet).
  final int? sizeBytes;
  final DateTime? modified;
  final bool isCurrent;

  const WorkspaceInfo({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modified,
    required this.isCurrent,
  });

  bool get hasFile => sizeBytes != null;
}

/// What a file about to be imported contains.
class ImportPreview {
  final String sourcePath;
  final String suggestedName;
  final DateTime? exportedAt;
  final String? exportedFrom;
  final String? scheduleStart;
  final String? scheduleEnd;
  final String? timeFormat;
  final int schemaVersion;
  final int machines;
  final int sequences;
  final int orders;

  const ImportPreview({
    required this.sourcePath,
    required this.suggestedName,
    required this.exportedAt,
    required this.exportedFrom,
    required this.scheduleStart,
    required this.scheduleEnd,
    required this.timeFormat,
    required this.schemaVersion,
    required this.machines,
    required this.sequences,
    required this.orders,
  });
}

class WorkspaceStore {
  final String baseDir;

  WorkspaceStore(this.baseDir);

  DatabaseFactory get _factory {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  File get _registry => File(p.join(baseDir, 'workspace.txt'));

  static String fileNameFor(String name) =>
      SQLLiteDatabaseProvider.fileNameFor(name);

  String dbPathFor(String name) => p.join(baseDir, fileNameFor(name));

  static const _suffix = '_v3.db';

  // ── Registry ─────────────────────────────────────────────────────────────

  Future<({String current, List<String> names})> _readRegistry() async {
    if (!await _registry.exists()) {
      return (current: kDefaultWorkspace, names: <String>[]);
    }
    final lines = (await _registry.readAsLines())
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return (current: kDefaultWorkspace, names: <String>[]);
    return (current: lines.first, names: lines.sublist(1));
  }

  Future<void> _writeRegistry(String current, Iterable<String> names) async {
    await Directory(baseDir).create(recursive: true);
    final unique = <String>[];
    for (final n in [current, ...names]) {
      if (n == kTutorialWorkspaceName) continue;
      if (!unique.any((u) => _sameFile(u, n))) unique.add(n);
    }
    await _registry.writeAsString([current, ...unique].join('\n'));
  }

  bool _sameFile(String a, String b) =>
      fileNameFor(a).toLowerCase() == fileNameFor(b).toLowerCase();

  /// The workspace opened at start-up.
  Future<String> currentName() async => (await _readRegistry()).current;

  Future<void> setCurrent(String name) async {
    final r = await _readRegistry();
    await _writeRegistry(name, [...r.names, r.current]);
  }

  /// Every workspace: those in the registry plus any database file found in
  /// the folder (e.g. "default", or one copied there by hand). The tutorial
  /// workspace is left out. The open one comes first, the rest by name.
  Future<List<WorkspaceInfo>> list() async {
    final r = await _readRegistry();
    final names = <String>[r.current, ...r.names];
    final dir = Directory(baseDir);
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final base = p.basename(e.path);
        if (!base.endsWith(_suffix)) continue;
        final stem = base.substring(0, base.length - _suffix.length);
        if (stem.isEmpty) continue;
        if (!names.any((n) => _sameFile(n, stem))) names.add(stem);
      }
    }
    final out = <WorkspaceInfo>[];
    for (final n in names) {
      if (n == kTutorialWorkspaceName) continue;
      if (out.any((w) => _sameFile(w.name, n))) continue;
      final f = File(dbPathFor(n));
      final exists = await f.exists();
      final stat = exists ? await f.stat() : null;
      out.add(WorkspaceInfo(
        name: n,
        path: f.path,
        sizeBytes: stat?.size,
        modified: stat?.modified,
        isCurrent: _sameFile(n, r.current),
      ));
    }
    out.sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  /// The workspace that [name] would use (same file), or null.
  Future<WorkspaceInfo?> find(String name) async {
    for (final w in await list()) {
      if (_sameFile(w.name, name.trim())) return w;
    }
    return null;
  }

  // ── Names ────────────────────────────────────────────────────────────────

  /// Why [name] cannot be used, or null when it can. [ignoring] is the
  /// workspace being renamed (it may keep its own name).
  Future<String?> validateName(String name, {String? ignoring}) async {
    final n = name.trim();
    if (n.isEmpty) return 'Escribe un nombre.';
    if (n.length > kMaxWorkspaceNameLength) {
      return 'Máximo $kMaxWorkspaceNameLength caracteres.';
    }
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(n)) {
      return r'No uses estos caracteres: \ / : * ? " < > |';
    }
    if (n.startsWith('.') || n.endsWith('.')) {
      return 'El nombre no puede empezar ni terminar en punto.';
    }
    if (_sameFile(n, kTutorialWorkspaceName)) {
      return '"$kTutorialWorkspaceName" está reservado para el tutorial.';
    }
    for (final w in await list()) {
      if (ignoring != null && _sameFile(w.name, ignoring)) continue;
      if (_sameFile(w.name, n)) {
        return w.name.toLowerCase() == n.toLowerCase()
            ? 'Ya existe un workspace con ese nombre.'
            : 'Se confunde con "${w.name}" (los espacios no cuentan).';
      }
    }
    return null;
  }

  Future<void> _requireValid(String name, {String? ignoring}) async {
    final error = await validateName(name, ignoring: ignoring);
    if (error != null) throw WorkspaceException(error);
  }

  /// "Planta A (2)", "Planta A (3)"... the first free variant of [name].
  Future<String> freeName(String name) async {
    var base = name.trim();
    if (base.isEmpty) base = 'Workspace';
    if (await validateName(base) == null) return base;
    for (var i = 2; i < 1000; i++) {
      final candidate = '$base ($i)';
      if (await validateName(candidate) == null) return candidate;
    }
    return '$base ${DateTime.now().millisecondsSinceEpoch}';
  }

  // ── Operations ───────────────────────────────────────────────────────────

  /// Registers a new, empty workspace. Its database is created (with the
  /// sample data of every new workspace) the first time it is opened.
  Future<String> create(String name) async {
    final n = name.trim();
    await _requireValid(n);
    final r = await _readRegistry();
    await _writeRegistry(r.current, [...r.names, n]);
    return n;
  }

  /// Renames a workspace that is NOT open (the session closes it first).
  Future<void> rename(String oldName, String newName) async {
    final n = newName.trim();
    await _requireValid(n, ignoring: oldName);
    final from = dbPathFor(oldName);
    final to = dbPathFor(n);
    if (await File(from).exists() && !p.equals(from, to)) {
      await _moveDb(from, to);
    } else if (await File(from).exists()) {
      // Same file (only the case or the spaces changed).
      final tmp = '$to.renaming';
      await _moveDb(from, tmp);
      await _moveDb(tmp, to);
    }
    final r = await _readRegistry();
    String swap(String x) => _sameFile(x, oldName) ? n : x;
    await _writeRegistry(swap(r.current), r.names.map(swap));
  }

  /// Copies [source] into a new workspace [newName]. [openDb] is the live
  /// connection when [source] is the open workspace (a consistent copy is
  /// made from it instead of copying a file in use).
  Future<String> duplicate(String source, String newName,
      {Database? openDb}) async {
    final n = newName.trim();
    await _requireValid(n);
    final to = dbPathFor(n);
    if (openDb != null) {
      await _vacuumInto(openDb, to);
    } else if (await File(dbPathFor(source)).exists()) {
      await File(dbPathFor(source)).copy(to);
    }
    if (await File(to).exists()) {
      await _withDb(to, (db) => writeSettings(db, {kSettingWorkspaceName: n}));
    }
    final r = await _readRegistry();
    await _writeRegistry(r.current, [...r.names, n]);
    return n;
  }

  /// Deletes a workspace for good. The open one cannot be deleted.
  Future<void> delete(String name) async {
    final r = await _readRegistry();
    if (_sameFile(name, r.current)) {
      throw const WorkspaceException(
          'No se puede eliminar el workspace abierto. Abre otro primero.');
    }
    await _deleteDb(dbPathFor(name));
    await _writeRegistry(
        r.current, r.names.where((x) => !_sameFile(x, name)));
  }

  /// Writes [name] to [destination] as a single self-contained file with
  /// its shift, time format and where/when it was exported. Pass [openDb]
  /// when [name] is the open workspace.
  Future<String> exportTo(String name, String destination,
      {Database? openDb, String? computerName}) async {
    final meta = {
      kSettingWorkspaceName: name,
      kSettingExportedAt: DateTime.now().toIso8601String(),
      kSettingExportedFrom: computerName ?? _hostName(),
    };
    final tmp = '$destination.exporting';
    await _deleteDb(tmp);
    if (openDb != null) {
      await writeSettings(openDb, meta);
      await _vacuumInto(openDb, tmp);
    } else {
      final src = dbPathFor(name);
      if (!await File(src).exists()) {
        throw const WorkspaceException(
            'Este workspace todavía no tiene datos: ábrelo una vez antes '
            'de exportarlo.');
      }
      await _withDb(src, (db) async {
        await writeSettings(db, meta);
        await _vacuumInto(db, tmp);
      });
    }
    await _deleteDb(destination);
    await File(tmp).rename(destination);
    return destination;
  }

  /// Opens [path] read-only and checks it is a workspace this version can
  /// open. Throws [WorkspaceException] with the reason otherwise.
  Future<ImportPreview> inspect(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const WorkspaceException('El archivo ya no existe.');
    }
    if (!await _hasSqliteHeader(file)) {
      throw const WorkspaceException(
          'El archivo no es un workspace de esta aplicación '
          '(no es una base de datos válida).');
    }
    Database? db;
    try {
      db = await _factory.openDatabase(path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => (r['name'] as String).toLowerCase())
          .toSet();
      final missing = kCoreTables.where((t) => !tables.contains(t)).toList();
      if (missing.isNotEmpty) {
        throw const WorkspaceException(
            'El archivo es una base de datos, pero no de un workspace de '
            'esta aplicación.');
      }
      final version = _firstInt(await db.rawQuery('PRAGMA user_version'));
      if (version > SQLLiteDatabaseProvider.schemaVersion) {
        throw const WorkspaceException(
            'El workspace se creó con una versión más nueva de la '
            'aplicación. Actualiza la aplicación en este equipo para '
            'abrirlo.');
      }
      final s = await readSettings(db);
      Future<int> count(String table) async =>
          _firstInt(await db!.rawQuery('SELECT COUNT(*) FROM $table'));
      final fromFile = _nameFromFile(path);
      return ImportPreview(
        sourcePath: path,
        suggestedName: (s[kSettingWorkspaceName]?.trim().isNotEmpty ?? false)
            ? s[kSettingWorkspaceName]!.trim()
            : fromFile,
        exportedAt: DateTime.tryParse(s[kSettingExportedAt] ?? ''),
        exportedFrom: s[kSettingExportedFrom],
        scheduleStart: s[kSettingScheduleStart],
        scheduleEnd: s[kSettingScheduleEnd],
        timeFormat: s[kSettingTimeFormat],
        schemaVersion: version,
        machines: await count('machines'),
        sequences: await count('sequences'),
        orders: await count('orders'),
      );
    } on WorkspaceException {
      rethrow;
    } catch (_) {
      throw const WorkspaceException(
          'No se pudo leer el archivo: puede estar dañado o incompleto.');
    } finally {
      await db?.close();
    }
  }

  /// Copies the workspace file at [sourcePath] into the app-support folder
  /// as [name] and returns the path of that copy (the official file from
  /// now on). With [replace] an existing workspace of that name is
  /// overwritten; it must not be open (the session closes it first).
  Future<String> importFrom(String sourcePath, String name,
      {bool replace = false}) async {
    final n = name.trim();
    await inspect(sourcePath);
    final existing = (await list()).where((w) => _sameFile(w.name, n));
    if (existing.isEmpty || !replace) {
      await _requireValid(n);
    }
    final to = dbPathFor(n);
    if (p.equals(p.absolute(sourcePath), p.absolute(to))) {
      throw const WorkspaceException(
          'Ese archivo ya es el de este workspace.');
    }
    final tmp = '$to.importing';
    await _deleteDb(tmp);
    await File(sourcePath).copy(tmp);
    await _withDb(tmp, (db) => writeSettings(db, {kSettingWorkspaceName: n}));
    await _deleteDb(to);
    await File(tmp).rename(to);
    // The name chosen now replaces whatever the old entry was called.
    final r = await _readRegistry();
    final current = _sameFile(r.current, n) ? n : r.current;
    await _writeRegistry(
        current, [...r.names.where((x) => !_sameFile(x, n)), n]);
    return to;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static int _firstInt(List<Map<String, Object?>> rows) {
    if (rows.isEmpty || rows.first.isEmpty) return 0;
    final v = rows.first.values.first;
    return v is int ? v : int.tryParse('$v') ?? 0;
  }

  Future<T> _withDb<T>(String path, Future<T> Function(Database db) f) async {
    final db = await _factory.openDatabase(path,
        options: OpenDatabaseOptions(singleInstance: false));
    try {
      return await f(db);
    } finally {
      await db.close();
    }
  }

  /// A consistent, compacted copy of [db] at [path] (works while open).
  static Future<void> _vacuumInto(Database db, String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
    await db.execute('VACUUM INTO ?', [path]);
  }

  static Future<bool> _hasSqliteHeader(File f) async {
    try {
      final raf = await f.open();
      try {
        final bytes = await raf.read(16);
        return String.fromCharCodes(bytes) == 'SQLite format 3\u0000';
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// The database and its side files (journal, WAL).
  static List<String> _dbFiles(String path) =>
      [path, '$path-journal', '$path-wal', '$path-shm'];

  static Future<void> _deleteDb(String path) async {
    for (final f in _dbFiles(path)) {
      final file = File(f);
      if (await file.exists()) await file.delete();
    }
  }

  static Future<void> _moveDb(String from, String to) async {
    final src = _dbFiles(from);
    final dst = _dbFiles(to);
    for (var i = 0; i < src.length; i++) {
      final f = File(src[i]);
      if (await f.exists()) await f.rename(dst[i]);
    }
  }

  static String _nameFromFile(String path) {
    var base = p.basenameWithoutExtension(path);
    if (base.endsWith('_v3')) base = base.substring(0, base.length - 3);
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    if (base.length > kMaxWorkspaceNameLength) {
      base = base.substring(0, kMaxWorkspaceNameLength).trim();
    }
    return base.isEmpty ? 'Workspace importado' : base;
  }

  static String _hostName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }
}
