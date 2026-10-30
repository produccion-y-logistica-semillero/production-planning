// lib/shared/tutorial/tutorial_controller.dart
//
// Interactive, game-style tutorial: the app darkens the screen, lights up
// the exact button or field to use, says what to do and waits until the
// user really does it. Widgets mark themselves with TutorialTarget (an id);
// a tour is a list of TutorialStep naming those ids. TutorialLayer (above
// every route and dialog) draws the spotlight and the instructions.
import 'package:flutter/material.dart';

/// What completes a step.
enum TutorialAdvance {
  /// The user taps the lit target.
  tap,

  /// The user types in the lit field and presses "Listo"; with
  /// [TutorialStep.expectText] the text must match it.
  text,

  /// The step ends by itself when [TutorialStep.waitFor] appears on screen
  /// (e.g. the station just created shows up in the list).
  visible,

  /// The step ends when the app reports [TutorialStep.event] (e.g. the
  /// program was saved).
  event,

  /// Explanation only: the user presses "Entendido".
  button,
}

class TutorialStep {
  final String chapter;
  final String title;
  final String text;

  /// Target to light up; null shows the message without a spotlight.
  final String? target;
  final TutorialAdvance advance;

  /// For [TutorialAdvance.text]: what to type (case and spaces ignored).
  final String? expectText;

  /// For [TutorialAdvance.visible]: target whose appearance ends the step.
  final String? waitFor;

  /// For [TutorialAdvance.event].
  final String? event;

  /// false lets the user touch the whole screen (date and time pickers,
  /// drop-down menus) and does not darken it.
  final bool blockOutside;

  const TutorialStep({
    required this.chapter,
    required this.title,
    required this.text,
    this.target,
    this.advance = TutorialAdvance.tap,
    this.expectText,
    this.waitFor,
    this.event,
    this.blockOutside = true,
  });
}

class TutorialTour {
  final String id;
  final String title;
  final List<TutorialStep> steps;
  const TutorialTour({
    required this.id,
    required this.title,
    required this.steps,
  });

  /// Chapter names in order, without repeats.
  List<String> get chapters {
    final out = <String>[];
    for (final s in steps) {
      if (out.isEmpty || out.last != s.chapter) out.add(s.chapter);
    }
    return out;
  }
}

/// A registered target: the element and, for text fields, its controller.
class TutorialAnchor {
  final GlobalKey key;
  final TextEditingController? text;
  final EdgeInsets inflate;
  TutorialAnchor(this.key, this.text, this.inflate);
}

class TutorialController extends ChangeNotifier {
  TutorialController._();
  static final TutorialController instance = TutorialController._();

  TutorialTour? _tour;
  int _index = 0;

  /// Called when the tour ends (finished or abandoned), e.g. to leave the
  /// tutorial workspace.
  Future<void> Function(bool finished)? onEnd;

  TutorialTour? get tour => _tour;
  int get index => _index;
  bool get active => _tour != null;
  TutorialStep? get step => _tour?.steps[_index];

  final Map<String, List<TutorialAnchor>> _anchors = {};

  void register(String id, TutorialAnchor anchor) {
    final list = _anchors.putIfAbsent(id, () => []);
    list.remove(anchor);
    list.add(anchor);
  }

  void unregister(String id, TutorialAnchor anchor) {
    _anchors[id]?.remove(anchor);
  }

  /// The visible element registered as [id] (the most recent one that is
  /// on stage), or null.
  TutorialAnchor? anchor(String id) {
    final list = _anchors[id];
    if (list == null) return null;
    for (final a in list.reversed) {
      final ctx = a.key.currentContext;
      if (ctx == null || !ctx.mounted) continue;
      if (!TickerMode.of(ctx)) continue; // covered route
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) return a;
    }
    return null;
  }

  void start(TutorialTour tour) {
    _tour = tour;
    _index = 0;
    notifyListeners();
  }

  void next() {
    final t = _tour;
    if (t == null) return;
    if (_index >= t.steps.length - 1) {
      _finish(true);
      return;
    }
    _index++;
    notifyListeners();
  }

  void back() {
    if (_tour == null || _index == 0) return;
    _index--;
    notifyListeners();
  }

  void exit() => _finish(false);

  void _finish(bool finished) {
    if (_tour == null) return;
    _tour = null;
    _index = 0;
    notifyListeners();
    onEnd?.call(finished);
  }

  /// Something happened in the app ("orderSaved", "timePicked", ...).
  void emit(String event) {
    final s = step;
    if (s != null && s.advance == TutorialAdvance.event && s.event == event) {
      next();
    }
  }
}

/// Shorthand for app code: `tutorial.emit('orderSaved')`.
final TutorialController tutorial = TutorialController.instance;

/// Marks [child] as the tutorial target [id]. Costs nothing while no tour
/// runs. [text] lets a step check what the user typed; [inflate] grows the
/// lit area (e.g. to cover a whole menu row, not only its icon).
class TutorialTarget extends StatefulWidget {
  final String id;
  final TextEditingController? text;
  final EdgeInsets inflate;
  final Widget child;

  const TutorialTarget({
    super.key,
    required this.id,
    this.text,
    this.inflate = EdgeInsets.zero,
    required this.child,
  });

  @override
  State<TutorialTarget> createState() => _TutorialTargetState();
}

class _TutorialTargetState extends State<TutorialTarget> {
  final GlobalKey _key = GlobalKey();
  late TutorialAnchor _anchor;

  @override
  void initState() {
    super.initState();
    _anchor = TutorialAnchor(_key, widget.text, widget.inflate);
    tutorial.register(widget.id, _anchor);
  }

  @override
  void didUpdateWidget(TutorialTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id ||
        old.text != widget.text ||
        old.inflate != widget.inflate) {
      tutorial.unregister(old.id, _anchor);
      _anchor = TutorialAnchor(_key, widget.text, widget.inflate);
      tutorial.register(widget.id, _anchor);
    }
  }

  @override
  void dispose() {
    tutorial.unregister(widget.id, _anchor);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
