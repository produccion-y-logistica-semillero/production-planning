// Workspaces on disk: listing, names, create / rename / duplicate / delete,
// and moving one to another computer (export to .ppws, validate, import as
// a copy or replacing the existing one). Also the per-workspace shift and
// time format that travel inside the file.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:production_planning/core/data/db/sqllite_database_provider.dart';
import 'package:production_planning/shared/duration_input.dart';
import 'package:production_planning/shared/workspace/workspace_settings.dart';
import 'package:production_planning/shared/workspace/workspace_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

late _FakePathProvider _paths;

/// A real workspace database (full schema and sample data) in [dir].
Future<Database> _openWorkspace(String dir, String name) async {
  _paths.path = dir;
  await SQLLiteDatabaseProvider.closeDatabaseConnection();
  return SQLLiteDatabaseProvider.open(name);
}

Future<int> _count(String path, String table) async {
  final db = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
  try {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return rows.first['c'] as int;
  } finally {
    await db.close();
  }
}

void main() {
  late Directory root;
  late String pc1;
  late String pc2;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _paths = _FakePathProvider('');
    PathProviderPlatform.instance = _paths;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pp_ws_');
    pc1 = p.join(root.path, 'pc1');
    pc2 = p.join(root.path, 'pc2');
    await Directory(pc1).create();
    await Directory(pc2).create();
  });

  tearDown(() async {
    await SQLLiteDatabaseProvider.closeDatabaseConnection();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  group('listing and names', () {
    test('lists "default" from its file even when not in the registry, '
        'and leaves the tutorial out', () async {
      await _openWorkspace(pc1, 'default');
      await SQLLiteDatabaseProvider.closeDatabaseConnection();
      await _openWorkspace(pc1, kTutorialWorkspaceName);
      await SQLLiteDatabaseProvider.closeDatabaseConnection();
      await File(p.join(pc1, 'workspace.txt'))
          .writeAsString('Planta A\nPlanta A');

      final store = WorkspaceStore(pc1);
      final names = (await store.list()).map((w) => w.name).toList();
      expect(names, ['Planta A', 'default']);
      final current = (await store.list()).first;
      expect(current.isCurrent, isTrue);
      expect(current.hasFile, isFalse); // registered, never opened
    });

    test('rejects empty, reserved, invalid and colliding names', () async {
      final store = WorkspaceStore(pc1);
      await store.create('Mi Planta');
      expect(await store.validateName('  '), isNotNull);
      expect(await store.validateName('Tutorial'), contains('reservado'));
      expect(await store.validateName('a/b'), contains('caracteres'));
      expect(await store.validateName('x' * 41), contains('40'));
      expect(await store.validateName('mi planta'), contains('Ya existe'));
      // Same file name once spaces are removed.
      expect(await store.validateName('MiPlanta'), contains('Se confunde'));
      expect(await store.validateName('Otra planta'), isNull);
      expect(await store.validateName('Mi Planta', ignoring: 'Mi Planta'),
          isNull);
      expect(await store.freeName('Mi Planta'), 'Mi Planta (2)');
    });
  });

  group('operations', () {
    test('create, rename, duplicate and delete', () async {
      final db = await _openWorkspace(pc1, 'Base');
      final store = WorkspaceStore(pc1);
      await store.setCurrent('Base');
      final machines = await _count(store.dbPathFor('Base'), 'machines');

      await store.duplicate('Base', 'Copia', openDb: db);
      expect(await _count(store.dbPathFor('Copia'), 'machines'), machines);

      await store.rename('Copia', 'Copia renombrada');
      expect(File(store.dbPathFor('Copia')).existsSync(), isFalse);
      expect(File(store.dbPathFor('Copia renombrada')).existsSync(), isTrue);

      await store.create('Vacío');
      expect((await store.list()).map((w) => w.name),
          containsAll(['Base', 'Copia renombrada', 'Vacío']));

      await expectLater(
          store.delete('Base'), throwsA(isA<WorkspaceException>()));
      await store.delete('Copia renombrada');
      expect(File(store.dbPathFor('Copia renombrada')).existsSync(), isFalse);
      expect((await store.list()).map((w) => w.name),
          isNot(contains('Copia renombrada')));
    });

    test('renaming the open workspace keeps it as the current one', () async {
      await _openWorkspace(pc1, 'Base');
      await SQLLiteDatabaseProvider.closeDatabaseConnection();
      final store = WorkspaceStore(pc1);
      await store.setCurrent('Base');
      await store.rename('Base', 'Planta Norte');
      expect(await store.currentName(), 'Planta Norte');
    });
  });

  group('moving a workspace to another computer', () {
    test('export on PC1, import on PC2: same data, shift and format',
        () async {
      final db = await _openWorkspace(pc1, 'Planta A');
      await writeSettings(db, const WorkspacePreferences(
        TimeOfDay(hour: 6, minute: 0),
        TimeOfDay(hour: 14, minute: 30),
        TimeInputFormat.hms,
      ).toSettings());
      await db.insert('sequences', {'name': 'Ruta exclusiva PC1'});
      final pc1Store = WorkspaceStore(pc1);
      await pc1Store.setCurrent('Planta A');

      final downloads = p.join(root.path, 'Descargas');
      await Directory(downloads).create();
      final file = p.join(downloads, 'Planta A.ppws');
      await pc1Store.exportTo('Planta A', file,
          openDb: db, computerName: 'PC-1');
      await SQLLiteDatabaseProvider.closeDatabaseConnection();
      expect(File(file).existsSync(), isTrue);

      final pc2Store = WorkspaceStore(pc2);
      final preview = await pc2Store.inspect(file);
      expect(preview.suggestedName, 'Planta A');
      expect(preview.exportedFrom, 'PC-1');
      expect(preview.exportedAt, isNotNull);
      expect(preview.scheduleStart, '06:00');
      expect(preview.scheduleEnd, '14:30');
      expect(preview.timeFormat, 'hms');
      expect(preview.schemaVersion, SQLLiteDatabaseProvider.schemaVersion);

      final internal = await pc2Store.importFrom(file, 'Planta A');
      expect(p.dirname(internal), pc2);
      expect((await pc2Store.list()).map((w) => w.name), contains('Planta A'));

      // Opened on PC2 it carries PC1's route, shift and format.
      final db2 = await _openWorkspace(pc2, 'Planta A');
      final routes = await db2.query('sequences',
          where: 'name = ?', whereArgs: ['Ruta exclusiva PC1']);
      expect(routes, hasLength(1));
      final prefs = await loadPreferences(
          db2,
          const WorkspacePreferences(TimeOfDay(hour: 8, minute: 0),
              TimeOfDay(hour: 17, minute: 0), TimeInputFormat.minutes));
      expect(prefs.start, const TimeOfDay(hour: 6, minute: 0));
      expect(prefs.end, const TimeOfDay(hour: 14, minute: 30));
      expect(prefs.format, TimeInputFormat.hms);
      // The picked file was not touched.
      expect(File(file).existsSync(), isTrue);
    });

    test('importing an existing name: refused unless replacing, or saved '
        'under a new name', () async {
      final db = await _openWorkspace(pc1, 'Planta A');
      await db.insert('sequences', {'name': 'Versión nueva'});
      final file = p.join(root.path, 'Planta A.ppws');
      await WorkspaceStore(pc1).exportTo('Planta A', file, openDb: db);
      await SQLLiteDatabaseProvider.closeDatabaseConnection();

      // PC2 already has an older "Planta A".
      await _openWorkspace(pc2, 'Planta A');
      await SQLLiteDatabaseProvider.closeDatabaseConnection();
      final store = WorkspaceStore(pc2);
      await store.setCurrent('default');

      await expectLater(store.importFrom(file, 'planta a'),
          throwsA(isA<WorkspaceException>()));

      await store.importFrom(file, 'Planta A', replace: true);
      final replaced = await databaseFactoryFfi.openDatabase(
          store.dbPathFor('Planta A'),
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      expect(
          await replaced.query('sequences',
              where: 'name = ?', whereArgs: ['Versión nueva']),
          hasLength(1));
      await replaced.close();

      final other = await store.freeName('Planta A');
      await store.importFrom(file, other);
      expect((await store.list()).map((w) => w.name),
          containsAll(['Planta A', 'Planta A (2)']));
    });

    test('rejects files that are not workspaces of this version', () async {
      final store = WorkspaceStore(pc2);

      final text = File(p.join(root.path, 'notas.ppws'));
      await text.writeAsString('esto no es una base de datos');
      await expectLater(
          store.inspect(text.path),
          throwsA(isA<WorkspaceException>().having(
              (e) => e.message, 'message', contains('no es un workspace'))));

      final foreign = p.join(root.path, 'otra.db');
      final fdb = await databaseFactoryFfi.openDatabase(foreign,
          options: OpenDatabaseOptions(singleInstance: false));
      await fdb.execute('CREATE TABLE clientes (id INTEGER)');
      await fdb.close();
      await expectLater(
          store.inspect(foreign),
          throwsA(isA<WorkspaceException>()
              .having((e) => e.message, 'message', contains('no de un'))));

      final db = await _openWorkspace(pc1, 'Futuro');
      await db.execute(
          'PRAGMA user_version = ${SQLLiteDatabaseProvider.schemaVersion + 1}');
      final future = p.join(root.path, 'futuro.ppws');
      await WorkspaceStore(pc1).exportTo('Futuro', future, openDb: db);
      await SQLLiteDatabaseProvider.closeDatabaseConnection();
      await expectLater(
          store.inspect(future),
          throwsA(isA<WorkspaceException>()
              .having((e) => e.message, 'message', contains('más nueva'))));
    });
  });

  test('a workspace without settings takes the ones in use and keeps them',
      () async {
    final db = await _openWorkspace(pc1, 'Viejo');
    await db.delete(kWorkspaceSettingsTable);
    const inUse = WorkspacePreferences(TimeOfDay(hour: 7, minute: 15),
        TimeOfDay(hour: 15, minute: 45), TimeInputFormat.hms);
    final first = await loadPreferences(db, inUse);
    expect(first.start, inUse.start);
    expect(first.format, TimeInputFormat.hms);

    final later = await loadPreferences(
        db,
        const WorkspacePreferences(TimeOfDay(hour: 8, minute: 0),
            TimeOfDay(hour: 17, minute: 0), TimeInputFormat.minutes));
    expect(later.start, const TimeOfDay(hour: 7, minute: 15));
    expect(later.end, const TimeOfDay(hour: 15, minute: 45));
    expect(later.format, TimeInputFormat.hms);
  });
}
