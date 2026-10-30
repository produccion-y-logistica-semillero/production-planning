// lib/shared/tutorial/tutorial_layer.dart
//
// Draws the running tour above the whole app, dialogs included (it wraps
// the Navigator through MaterialApp.builder): a dark veil with a lit hole
// over the target, a pulsing ring, and a speech bubble with the
// instruction. Only the hole lets touches through, so the user can only do
// what the step asks; the step advances when they do it.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';

class TutorialLayer extends StatefulWidget {
  final Widget child;
  const TutorialLayer({super.key, required this.child});

  @override
  State<TutorialLayer> createState() => _TutorialLayerState();
}

class _TutorialLayerState extends State<TutorialLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _poll;

  /// Lit area of the current step, in screen coordinates.
  Rect? _hole;
  int _stepKey = -1;
  DateTime _stepStarted = DateTime.now();
  bool _scrolled = false;
  bool _confirmExit = false;
  TextEditingController? _listenedText;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    tutorial.addListener(_onTutorial);
    _onTutorial();
  }

  @override
  void dispose() {
    tutorial.removeListener(_onTutorial);
    _poll?.cancel();
    _listenedText?.removeListener(_onText);
    _pulse.dispose();
    super.dispose();
  }

  void _onTutorial() {
    if (!tutorial.active) {
      _poll?.cancel();
      _poll = null;
      _listenText(null);
      if (mounted) setState(() => _hole = null);
      return;
    }
    final key = tutorial.index;
    if (key != _stepKey) {
      _stepKey = key;
      _stepStarted = DateTime.now();
      _scrolled = false;
      _confirmExit = false;
      _hole = null;
    }
    _poll ??= Timer.periodic(const Duration(milliseconds: 120), (_) => _tick());
    _tick();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  void _listenText(TextEditingController? c) {
    if (identical(c, _listenedText)) return;
    _listenedText?.removeListener(_onText);
    _listenedText = c;
    c?.addListener(_onText);
  }

  /// Follows the target (it may scroll or animate) and checks whether a
  /// "visible" step is done.
  void _tick() {
    final step = tutorial.step;
    if (step == null || !mounted) return;

    if (step.advance == TutorialAdvance.visible && step.waitFor != null) {
      if (tutorial.anchor(step.waitFor!) != null) {
        tutorial.next();
        return;
      }
    }

    Rect? hole;
    final id = step.target;
    final anchor = id == null ? null : tutorial.anchor(id);
    if (anchor != null) {
      final ctx = anchor.key.currentContext!;
      final box = ctx.findRenderObject() as RenderBox;
      final layerBox = context.findRenderObject() as RenderBox?;
      final origin = box.localToGlobal(Offset.zero, ancestor: layerBox);
      final r = origin & box.size;
      hole = Rect.fromLTRB(
        r.left - 6 - anchor.inflate.left,
        r.top - 6 - anchor.inflate.top,
        r.right + 6 + anchor.inflate.right,
        r.bottom + 6 + anchor.inflate.bottom,
      );
      if (!_scrolled) {
        // Bring it into its scroll view's visible area; each call is a
        // no-op when that edge is already visible.
        _scrolled = true;
        Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 250),
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd)
            .then((_) {
          if (ctx.mounted) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 250),
                alignmentPolicy:
                    ScrollPositionAlignmentPolicy.keepVisibleAtStart);
          }
        });
      }
    }
    _listenText(anchor?.text);
    if (hole != _hole) setState(() => _hole = hole);
  }

  bool _textOk(TutorialStep step) {
    final text = _listenedText?.text ?? '';
    String norm(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (step.expectText == null) return norm(text).isNotEmpty;
    return norm(text) == norm(step.expectText!);
  }

  void _onPointerUp(PointerUpEvent e) {
    final step = tutorial.step;
    final hole = _hole;
    if (step == null || hole == null) return;
    if (step.advance != TutorialAdvance.tap) return;
    if (!hole.contains(e.position)) return;
    final index = tutorial.index;
    // Let the app handle the tap first (open the dialog, change page).
    Future.delayed(const Duration(milliseconds: 200), () {
      if (tutorial.active && tutorial.index == index) tutorial.next();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tutorial,
      builder: (context, _) {
        final step = tutorial.step;
        return Stack(
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerUp: _onPointerUp,
              child: widget.child,
            ),
            if (step != null) ..._overlay(context, step),
          ],
        );
      },
    );
  }

  List<Widget> _overlay(BuildContext context, TutorialStep step) {
    final waiting = step.target != null && _hole == null;
    return [
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => _HoleBarrier(
            hole: _hole,
            // While the target is not on screen yet (a page or dialog is
            // opening), nothing is blocked.
            block: step.blockOutside && !waiting,
            dim: step.blockOutside && !waiting,
            pulse: _pulse.value,
          ),
        ),
      ),
      _bubble(context, step, waiting),
    ];
  }

  Widget _bubble(BuildContext context, TutorialStep step, bool waiting) {
    final theme = Theme.of(context);
    final tour = tutorial.tour!;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(380.0, size.width - 32);
    final hole = _hole;
    final slow = waiting &&
        DateTime.now().difference(_stepStarted) > const Duration(seconds: 3);

    final card = Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.school, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(step.chapter,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                ),
                Text('${tutorial.index + 1}/${tour.steps.length}',
                    style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (tutorial.index + 1) / tour.steps.length,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 10),
            Text(step.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(step.text),
            if (step.expectText != null) ...[
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  const Icon(Icons.keyboard_outlined, size: 18),
                  Text('Escribe:', style: theme.textTheme.bodySmall),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(step.expectText!,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
            if (slow) ...[
              const SizedBox(height: 6),
              Text(
                'Esperando a que aparezca en pantalla… Si no aparece, '
                'vuelve un paso atrás o usa "Saltar".',
                style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            if (_confirmExit)
              Row(
                children: [
                  const Expanded(child: Text('¿Salir del tutorial?')),
                  TextButton(
                    onPressed: () => setState(() => _confirmExit = false),
                    child: const Text('No'),
                  ),
                  FilledButton(
                    onPressed: tutorial.exit,
                    child: const Text('Sí, salir'),
                  ),
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _confirmExit = true),
                    child: const Text('Salir'),
                  ),
                  if (tutorial.index > 0)
                    TextButton(
                      onPressed: tutorial.back,
                      child: const Text('Atrás'),
                    ),
                  if (step.advance != TutorialAdvance.button)
                    TextButton(
                      onPressed: tutorial.next,
                      child: const Text('Saltar'),
                    ),
                  if (step.advance == TutorialAdvance.text)
                    FilledButton(
                      onPressed: _textOk(step) ? tutorial.next : null,
                      child: const Text('Listo'),
                    ),
                  if (step.advance == TutorialAdvance.button)
                    FilledButton(
                      onPressed: tutorial.next,
                      child: Text(tutorial.index == tour.steps.length - 1
                          ? 'Terminar'
                          : 'Entendido'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );

    if (hole == null) {
      if (!step.blockOutside || waiting) {
        // Out of the way of pickers and opening pages.
        return Positioned(top: 16, right: 16, child: card);
      }
      return Positioned.fill(child: Center(child: card));
    }
    final left = (hole.center.dx - width / 2)
        .clamp(16.0, math.max(16.0, size.width - width - 16))
        .toDouble();
    final below = size.height - hole.bottom;
    final above = hole.top;
    if (below >= 260 || below >= above) {
      return Positioned(
          left: left,
          top: math.min(hole.bottom + 14, size.height - 120).toDouble(),
          child: card);
    }
    return Positioned(
        left: left,
        bottom:
            math.min(size.height - hole.top + 14, size.height - 120).toDouble(),
        child: card);
  }
}

/// Dark veil with a hole. Touches inside the hole (and everywhere, when
/// [block] is false) go through to the app.
class _HoleBarrier extends LeafRenderObjectWidget {
  final Rect? hole;
  final bool block;
  final bool dim;
  final double pulse;

  const _HoleBarrier({
    required this.hole,
    required this.block,
    required this.dim,
    required this.pulse,
  });

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHoleBarrier(
      hole, block, dim, pulse, Theme.of(context).colorScheme.primary);

  @override
  void updateRenderObject(
      BuildContext context, _RenderHoleBarrier renderObject) {
    renderObject
      ..hole = hole
      ..block = block
      ..dim = dim
      ..pulse = pulse
      ..accent = Theme.of(context).colorScheme.primary;
  }
}

class _RenderHoleBarrier extends RenderBox {
  _RenderHoleBarrier(this._hole, this._block, this._dim, this._pulse,
      this._accent);

  Rect? _hole;
  set hole(Rect? v) {
    if (v == _hole) return;
    _hole = v;
    markNeedsPaint();
  }

  bool _block;
  set block(bool v) => _block = v;

  bool _dim;
  set dim(bool v) {
    if (v == _dim) return;
    _dim = v;
    markNeedsPaint();
  }

  double _pulse;
  set pulse(double v) {
    if (v == _pulse) return;
    _pulse = v;
    markNeedsPaint();
  }

  Color _accent;
  set accent(Color v) {
    if (v == _accent) return;
    _accent = v;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_block) return false;
    final h = _hole;
    if (h != null && h.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final screen = offset & size;
    final h = _hole?.shift(offset);
    final rrect =
        h == null ? null : RRect.fromRectAndRadius(h, const Radius.circular(12));
    if (_dim) {
      final path = Path()..addRect(screen);
      if (rrect != null) {
        path
          ..addRRect(rrect)
          ..fillType = PathFillType.evenOdd;
      }
      canvas.drawPath(path, Paint()..color = const Color(0xB3000000));
    }
    if (rrect != null) {
      canvas.drawRRect(
        rrect.inflate(2 + 4 * _pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _accent.withValues(alpha: 1 - 0.6 * _pulse),
      );
    }
  }
}
