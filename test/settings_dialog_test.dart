// The Configuración dialog lays out without overflow on a wide and on a
// narrow window, shows the three sections, and saving the shift writes it
// to the open workspace.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:production_planning/core/data/db/sqllite_database_provider.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/settings_dialog.dart';
import 'package:production_planning/shared/workspace/workspace_session.dart';
import 'package:production_planning/shared/workspace/workspace_settings.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getDownloadsPath() async => path;
}

Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _open(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showSettingsDialog(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await settle(tester, rounds: 20);
}

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pp_settings_');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await initDependencies('default');
    openWorkspaceName.value = 'default';
  });

  for (final size in const [Size(1366, 900), Size(720, 560)]) {
    testWidgets('three sections render at ${size.width.toInt()} px',
        (tester) async {
      await _open(tester, size);
      expect(find.text('Configuración'), findsOneWidget);
      expect(find.text('Archivo oficial de este workspace'.toUpperCase()),
          findsOneWidget);

      await tester.tap(find.byIcon(Icons.schedule).first);
      await settle(tester);
      expect(find.text('Turno de trabajo'.toUpperCase()), findsOneWidget);

      await tester.tap(find.byIcon(Icons.timer_outlined).first);
      await settle(tester);
      expect(find.text('Todo en minutos'), findsOneWidget);
      expect(find.text('Todo en hh:mm:ss'), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar'));
      await settle(tester);
      expect(find.text('Configuración'), findsNothing);
    });
  }

  testWidgets('saving the time format stores it in the open workspace',
      (tester) async {
    await _open(tester, const Size(1366, 900));
    await tester.tap(find.byIcon(Icons.timer_outlined).first);
    await settle(tester);
    await tester.tap(find.text('Todo en hh:mm:ss'));
    await settle(tester, rounds: 1);
    expect(find.text('Cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    final stored = await tester.runAsync(
        () => readSettings(SQLLiteDatabaseProvider.current!));
    expect(stored![kSettingTimeFormat], 'hms');
    expect(find.text('Todo guardado'), findsOneWidget);
  });
}
