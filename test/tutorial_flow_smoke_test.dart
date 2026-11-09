// Runs the start of the Flow Shop guided tour on the real app (real
// temporary database, real dialogs): the steps must find their targets,
// accept the user's taps and typing through the lit hole, and advance —
// up to the first station appearing in the list.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/main.dart';
import 'package:production_planning/presentation/main_page/presentation/pages/main_page.dart';
import 'package:production_planning/presentation/main_page/presentation/provider/side_menu_provider.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:production_planning/shared/tutorial/tutorial_layer.dart';
import 'package:production_planning/shared/tutorial/tutorial_tours.dart';
import 'package:production_planning/shared/tutorial/tutorial_workspace.dart';
import 'package:provider/provider.dart';

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
}

Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Center of the lit target of the current step.
Offset targetCenter(String id) {
  final ctx = tutorial.anchor(id)!.key.currentContext!;
  final box = ctx.findRenderObject() as RenderBox;
  return box.localToGlobal(box.size.center(Offset.zero));
}

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pp_tutorial_');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await initDependencies('smoke');
  });

  testWidgets('the tour opens the Tutorial workspace and leaves it at the end',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MyApp());
    await settle(tester);
    expect(inTutorialWorkspace, isFalse);

    // Started from the manual's button.
    // Not awaited: settle() lets the database work finish while frames run.
    // ignore: unawaited_futures
    startGuidedTour(flowShopTour);
    await settle(tester, rounds: 12);
    expect(inTutorialWorkspace, isTrue);
    expect(tutorial.active, isTrue);
    expect(find.text('Programación de Operaciones'), findsWidgets);

    tutorial.exit();
    await settle(tester, rounds: 12);
    expect(inTutorialWorkspace, isFalse);
    expect(find.text('Programación de Operaciones'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('Flow Shop tour: settings and the first station', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => TutorialLayer(child: child!),
      home: ChangeNotifierProvider(
        create: (_) => SideMenuProvider(),
        child: MainPage(),
      ),
    ));
    await settle(tester);
    tutorial.start(flowShopTour);
    await settle(tester);

    Future<void> tapTarget(String id) async {
      await tester.tapAt(targetCenter(id));
      await settle(tester);
    }

    Future<void> next() async {
      await tester.tap(find.text('Entendido'));
      await settle(tester);
    }

    String step() => tutorial.step!.title;

    await next(); // welcome
    expect(step(), 'Configuración');
    await tapTarget('menu.config');
    expect(step(), 'El horario de la planta');
    await tapTarget('config.nav.horario');
    expect(step(), 'Inicio y fin del turno');
    await next();
    expect(step(), 'Formato de tiempos');
    await tapTarget('config.nav.formato');
    expect(step(), 'Minutos u hh:mm:ss');
    await next();
    expect(step(), 'Cerrar la configuración');
    await tapTarget('config.close');
    expect(step(), 'Notación teórica');
    await tapTarget('menu.notacion');
    expect(step(), 'Estaciones de trabajo');
    await tapTarget('menu/machines');
    expect(step(), 'Notación de esta pantalla');
    await next();

    expect(step(), 'Nueva estación: Mezcla');
    await tapTarget('machines.addStation');
    expect(step(), 'Nombre de la estación');
    await tester.enterText(
        find.descendant(
            of: find.byWidget(
                tutorial.anchor('station.name')!.key.currentWidget!),
            matching: find.byType(TextField)),
        'Mezcla');
    await settle(tester);
    await tester.tap(find.text('Listo'));
    await settle(tester);
    expect(step(), 'Descripción (opcional)');
    await tester.enterText(
        find.descendant(
            of: find.byWidget(
                tutorial.anchor('station.desc')!.key.currentWidget!),
            matching: find.byType(TextField)),
        'Amasado');
    await settle(tester);
    await tester.tap(find.text('Listo'));
    await settle(tester);
    expect(step(), 'Agregar');
    await tapTarget('station.add');
    await settle(tester, rounds: 10);
    // The station shows up in the list and the tour moves on by itself.
    expect(step(), 'Nueva estación: Horno');

    Future<void> type(String id, String text) async {
      await tester.enterText(
          find.descendant(
              of: find.byWidget(tutorial.anchor(id)!.key.currentWidget!),
              matching: find.byType(TextField)),
          text);
      await settle(tester);
      await tester.tap(find.text('Listo'));
      await settle(tester);
    }

    for (final s in ['Horno', 'Empaque']) {
      expect(step(), 'Nueva estación: $s');
      await tapTarget('machines.addStation');
      await type('station.name', s);
      await type('station.desc', 'x');
      await tapTarget('station.add');
      await settle(tester, rounds: 10);
    }

    // First machine: the + of Mezcla opens the machine dialog.
    expect(step(), 'Máquina para Mezcla');
    await tapTarget('station.addMachine:Mezcla');
    await type('machine.name', 'Mezcladora');
    expect(step(), 'Disponible desde ahora');
    await tester.tap(find.text('Ahora'));
    await settle(tester);
    expect(step(), 'Descansos automáticos');
    await next();
    await next(); // maintenance
    expect(step(), 'Agregar la máquina');
    await tapTarget('machine.add');
    await settle(tester, rounds: 10);
    expect(step(), 'Máquina para Horno');

    tutorial.exit();
    await settle(tester, rounds: 2);
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });
}
