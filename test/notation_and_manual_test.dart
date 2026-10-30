import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/presentation/main_page/presentation/pages/manual_page.dart';
import 'package:production_planning/presentation/main_page/presentation/pages/notation_glossary_page.dart';
import 'package:production_planning/presentation/main_page/presentation/provider/side_menu_provider.dart';
import 'package:production_planning/shared/notation.dart';
import 'package:provider/provider.dart';

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => SideMenuProvider(),
    child: MaterialApp(home: page),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('catálogo de notación', () {
    test('every rule with help has its formula', () {
      for (final code in [
        'EDD', 'SPT', 'LPT', 'FIFO', 'WSPT', 'MS', 'MINSLACK', 'CR', 'ATCS',
        'LWR', 'MWR', 'JOHNSON', 'CDS', 'GENETICS', 'TABU',
        'PRIORIDAD_COMPUESTA', 'SECUENCIA_USUARIO', 'EDD_ADAPTADO',
      ]) {
        expect(notationForRule(code), isNotNull, reason: code);
      }
    });

    test('three-field notation of the detected environment', () {
      expect(alphaFor('FLOW SHOP'), 'Fm');
      expect(alphaFor('FLEXIBLE JOB SHOP'), 'FJc');
      expect(threeFieldFor('FLEXIBLE JOB SHOP'), startsWith('FJc | rj, sjk'));
      expect(betaFor('RECURRENTE'), contains('recrc'));
    });

    test('machines are written Mi in the literature', () {
      final machine = kNotation.firstWhere((e) => e.symbol == 'i (Mi)');
      expect(machine.contexts, contains(NotationContext.machines));
    });

    test('withSymbol only adds the symbol while the switch is on', () {
      showNotation.value = false;
      expect(withSymbol('Prioridad', 'wj'), 'Prioridad');
      showNotation.value = true;
      expect(withSymbol('Prioridad', 'wj'), 'Prioridad (wj)');
      showNotation.value = false;
    });
  });

  testWidgets('manual shows both guided cases and advances step by step',
      (tester) async {
    await _pump(tester, const ManualPage());
    expect(find.text('Caso 1 · Flow Shop'), findsOneWidget);
    expect(find.text('Caso 2 · Flexible Job Shop'), findsOneWidget);
    expect(find.text('Paso 1 de 8'), findsOneWidget);

    await tester.tap(find.text('Listo, siguiente').first);
    await tester.pumpAndSettle();
    expect(find.text('Paso 2 de 8'), findsOneWidget);

    await tester.tap(find.text('Caso 2 · Flexible Job Shop'));
    await tester.pumpAndSettle();
    expect(find.text('Paso 1 de 7'), findsOneWidget);
  });

  testWidgets('glossary search finds Johnson', (tester) async {
    await _pump(tester, const NotationGlossaryPage());
    await tester.enterText(find.byType(TextField), 'johnson');
    await tester.pumpAndSettle();
    expect(find.text('Regla de Johnson (1954)'), findsOneWidget);
    expect(find.text('Makespan'), findsNothing);
  });
}
