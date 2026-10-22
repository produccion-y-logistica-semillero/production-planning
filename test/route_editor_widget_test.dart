// Smoke test of the route editor canvas: it lays out without errors in edit
// and read-only mode, adds stations, refuses a repeated one, opens no
// information panel, deletes from the toolbar, and Conectar starts from the
// selected station.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/entities/route_draft.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/graph_editor.dart';

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 1200, height: 700, child: child)),
    );

void main() {
  testWidgets('edit mode: add, refuse a repeat, select, delete',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<NodeEditorState>();
    await tester.pumpWidget(host(NodeEditor(key: key)));
    await tester.pumpAndSettle();

    final oven = MachineTypeEntity(id: 1, name: 'Horno', description: '');
    expect(key.currentState!.addStation(oven), isTrue);
    await tester.pumpAndSettle();
    // No information panel opens on selection.
    expect(find.text('Tiempo estándar'), findsNothing);

    expect(key.currentState!.addStation(oven), isFalse);
    await tester.pumpAndSettle();
    expect(find.textContaining('ya está en la ruta'), findsOneWidget);

    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(key.currentState!.currentNodes(), isEmpty);
  });

  testWidgets('Conectar starts the arrow from the selected station',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<NodeEditorState>();
    await tester.pumpWidget(host(NodeEditor(key: key)));
    await tester.pumpAndSettle();
    final editor = key.currentState!;
    editor.addStation(MachineTypeEntity(id: 1, name: 'Corte', description: ''));
    editor.addStation(MachineTypeEntity(id: 2, name: 'Horno', description: ''));
    await tester.pumpAndSettle();
    // "Horno" (the last added) is selected. Pick Conectar: the hint asks
    // straight away for the DESTINATION.
    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('estación de destino'), findsOneWidget);
  });

  testWidgets('read-only mode shows a saved route without the edit toolbar',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final draft = RouteDraft(
      sequenceId: 1,
      name: 'Pan',
      nodes: [
        RouteNode(key: 10, taskId: 10, machineTypeId: 1, machineName: 'Mezcla'),
        RouteNode(key: 11, taskId: 11, machineTypeId: 2, machineName: 'Horno'),
      ],
      arrows: const [RouteArrow(10, 11)],
    );
    final key = GlobalKey<NodeEditorState>();
    await tester.pumpWidget(
        host(NodeEditor(key: key, readOnly: true, initialDraft: draft)));
    await tester.pumpAndSettle();

    expect(find.text('Ver todo'), findsOneWidget);
    expect(find.text('Conectar'), findsNothing);
    expect(key.currentState!.currentNodes().map((n) => n.key), [10, 11]);
    expect(key.currentState!.currentArrows(), [const RouteArrow(10, 11)]);
  });
}
