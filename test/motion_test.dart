// The shared motion widgets: entrances finish within the motion budget,
// collapse to nothing when the system asks for reduced motion, play once per
// item inside an EntranceScope, hover lifts, and showAppDialog behaves like
// showDialog.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/shared/motion/motion.dart';

double _opacityOf(WidgetTester tester, Finder f) => tester
    .widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first)
    .opacity;

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('FadeSlideIn ends fully visible within the motion budget',
      (tester) async {
    await tester.pumpWidget(_app(FadeSlideIn.staggered(
        index: 50, child: const Text('item')))); // capped delay
    expect(_opacityOf(tester, find.text('item')), 0);
    await tester.pump(Motion.staggerMax + Motion.slow);
    expect(_opacityOf(tester, find.text('item')), 1);
    expect(
        tester
            .widget<Transform>(find
                .ancestor(of: find.text('item'), matching: find.byType(Transform))
                .first)
            .transform
            .getTranslation()
            .y,
        0);
  });

  testWidgets('with reduced motion it appears at once', (tester) async {
    await tester.pumpWidget(
        _app(const FadeSlideIn(child: Text('item')), reduced: true));
    expect(_opacityOf(tester, find.text('item')), 1);
  });

  testWidgets('inside an EntranceScope each id animates only once',
      (tester) async {
    Widget list(bool show) => _app(EntranceScope(
          child: Column(children: [
            if (show) const FadeSlideIn(id: 'a', child: Text('a')),
          ]),
        ));
    await tester.pumpWidget(list(true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(list(false));
    await tester.pumpWidget(list(true)); // rebuilt, e.g. scrolled back
    expect(_opacityOf(tester, find.text('a')), 1);
  });

  testWidgets('HoverLift raises the child while the mouse is over it',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(HoverLift(
      onTap: () => taps++,
      child: const SizedBox(width: 100, height: 60, child: Text('card')),
    )));
    double lift() => tester
        .widget<AnimatedContainer>(find.byType(AnimatedContainer))
        .transform!
        .getTranslation()
        .y;
    expect(lift(), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('card')));
    await tester.pumpAndSettle();
    expect(lift(), lessThan(0));

    await tester.tap(find.text('card'));
    expect(taps, 1);

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(lift(), 0);
  });

  testWidgets('showAppDialog returns the value the dialog pops',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    final result = showAppDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        content: TextButton(
          onPressed: () => Navigator.of(c).pop('ok'),
          child: const Text('aceptar'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('aceptar'));
    await tester.pumpAndSettle();
    expect(await result, 'ok');
    expect(find.byType(AlertDialog), findsNothing);
  });
}
