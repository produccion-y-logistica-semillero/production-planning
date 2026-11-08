import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:production_planning/shared/tutorial/tutorial_layer.dart';
import 'package:production_planning/shared/tutorial/tutorial_tours.dart';

/// A tiny screen with a button, a field and a counter, under the layer.
class _Screen extends StatefulWidget {
  const _Screen();
  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  final name = TextEditingController();
  int taps = 0;
  int outside = 0;
  bool showDone = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            TutorialTarget(
              id: 't.button',
              child: ElevatedButton(
                onPressed: () => setState(() => taps++),
                child: const Text('Botón'),
              ),
            ),
            const SizedBox(height: 200),
            ElevatedButton(
              onPressed: () => setState(() => outside++),
              child: const Text('Fuera'),
            ),
            TutorialTarget(
              id: 't.field',
              text: name,
              child: SizedBox(width: 200, child: TextField(controller: name)),
            ),
            if (showDone) const TutorialTarget(id: 't.done', child: Text('ok')),
          ],
        ),
      );
}

Future<_ScreenState> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => TutorialLayer(child: child!),
    home: const _Screen(),
  ));
  return tester.state<_ScreenState>(find.byType(_Screen));
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  tearDown(() {
    if (tutorial.active) tutorial.exit();
    tutorial.onEnd = null;
  });

  testWidgets('a tap step lights the target, blocks the rest and advances',
      (tester) async {
    final screen = await _pump(tester);
    tutorial.start(const TutorialTour(id: 't', title: 't', steps: [
      TutorialStep(chapter: 'c', title: 'Toca', text: 'x', target: 't.button'),
      TutorialStep(
          chapter: 'c', title: 'Fin', text: 'y', advance: TutorialAdvance.button),
    ]));
    await _settle(tester);
    expect(find.text('Toca'), findsOneWidget);

    // Outside the hole nothing happens.
    await tester.tap(find.text('Fuera'), warnIfMissed: false);
    await _settle(tester);
    expect(screen.outside, 0);
    expect(tutorial.index, 0);

    // Inside the hole the app gets the tap and the step advances.
    await tester.tap(find.text('Botón'));
    await _settle(tester);
    expect(screen.taps, 1);
    expect(tutorial.index, 1);
  });

  testWidgets('a text step enables "Listo" only with the expected text',
      (tester) async {
    final screen = await _pump(tester);
    tutorial.start(const TutorialTour(id: 't', title: 't', steps: [
      TutorialStep(
        chapter: 'c',
        title: 'Escribe',
        text: 'x',
        target: 't.field',
        advance: TutorialAdvance.text,
        expectText: 'Mezcla',
      ),
      TutorialStep(
          chapter: 'c', title: 'Fin', text: 'y', advance: TutorialAdvance.button),
    ]));
    await _settle(tester);
    FilledButton listo() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Listo'));
    expect(listo().onPressed, isNull);

    screen.name.text = '  mezcla ';
    await _settle(tester);
    expect(listo().onPressed, isNotNull);
    await tester.tap(find.text('Listo'));
    await _settle(tester);
    expect(tutorial.index, 1);
  });

  testWidgets('event and visible steps advance by themselves', (tester) async {
    final screen = await _pump(tester);
    var ended = false;
    tutorial.onEnd = (finished) async => ended = finished;
    tutorial.start(const TutorialTour(id: 't', title: 't', steps: [
      TutorialStep(
        chapter: 'c',
        title: 'Evento',
        text: 'x',
        advance: TutorialAdvance.event,
        event: 'saved',
      ),
      TutorialStep(
        chapter: 'c',
        title: 'Aparece',
        text: 'y',
        advance: TutorialAdvance.visible,
        waitFor: 't.done',
      ),
    ]));
    await _settle(tester);
    tutorial.emit('other');
    expect(tutorial.index, 0);
    tutorial.emit('saved');
    await _settle(tester);
    expect(tutorial.index, 1);

    screen.setState(() => screen.showDone = true);
    await _settle(tester);
    expect(tutorial.active, isFalse);
    expect(ended, isTrue);
  });

  test('every tour step is well formed', () {
    for (final tour in kTours) {
      expect(tour.steps.length, greaterThan(40), reason: tour.id);
      for (final s in tour.steps) {
        final where = '${tour.id}: ${s.title}';
        switch (s.advance) {
          case TutorialAdvance.tap:
          case TutorialAdvance.text:
            expect(s.target, isNotNull, reason: where);
          case TutorialAdvance.visible:
            expect(s.waitFor, isNotNull, reason: where);
          case TutorialAdvance.event:
            expect(s.event, isNotNull, reason: where);
          case TutorialAdvance.button:
            break;
        }
      }
    }
  });
}
