// lib/shared/motion/motion.dart
//
// One motion language for the whole app: short, calm transitions (fade plus
// a small offset), a light lift on hover and lists that appear in a quick
// cascade. Durations and curves live here so the feel can be tuned in one
// place. When Windows has animations turned off (accessibility), every
// animation collapses to zero.
import 'package:flutter/material.dart';

/// Motion tokens.
abstract final class Motion {
  /// Hover and press feedback.
  static const Duration fast = Duration(milliseconds: 150);

  /// State changes, dialogs, expanding panels.
  static const Duration medium = Duration(milliseconds: 220);

  /// Page transitions and list entrances.
  static const Duration slow = Duration(milliseconds: 300);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// Delay between consecutive items of a list entrance, and the longest
  /// delay any item waits (so long lists do not feel slow).
  static const Duration staggerStep = Duration(milliseconds: 30);
  static const Duration staggerMax = Duration(milliseconds: 300);
}

/// False when the system asks for reduced motion.
bool motionEnabled(BuildContext context) =>
    !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

/// [d] or zero when motion is disabled.
Duration motionDuration(BuildContext context, Duration d) =>
    motionEnabled(context) ? d : Duration.zero;

// ── Page transition ─────────────────────────────────────────────────────────

/// Pages fade in while rising slightly; the page below fades out. Used for
/// every MaterialPageRoute through the theme.
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.slow;

  @override
  Duration get reverseTransitionDuration => Motion.medium;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!motionEnabled(context)) return child;
    final enter = CurvedAnimation(
        parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
    final leave =
        CurvedAnimation(parent: secondaryAnimation, curve: Motion.exit);
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(leave),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.012), end: Offset.zero)
              .animate(enter),
          child: child,
        ),
      ),
    );
  }
}

/// The app theme's page transitions (fade-through on every platform).
const PageTransitionsTheme kAppPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.fuchsia: FadeThroughPageTransitionsBuilder(),
  },
);

// ── Dialogs ─────────────────────────────────────────────────────────────────

/// A DialogRoute that fades in and grows from 96 % instead of only fading.
class _AppDialogRoute<T> extends DialogRoute<T> {
  _AppDialogRoute({
    required super.context,
    required super.builder,
    super.barrierDismissible,
    super.barrierColor,
    super.barrierLabel,
    super.settings,
    super.themes,
  });

  @override
  Duration get transitionDuration => Motion.medium;

  @override
  Duration get reverseTransitionDuration => Motion.fast;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (!motionEnabled(context)) return child;
    final curved = CurvedAnimation(
        parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

/// Same as [showDialog] (same arguments and result) with the app's dialog
/// transition.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(_AppDialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ?? Colors.black54,
    barrierLabel: barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    settings: routeSettings,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  ));
}

// ── Entrance ────────────────────────────────────────────────────────────────

/// Remembers which items of a list already played their entrance, so an
/// item scrolled away and back (rebuilt by ListView) does not animate again.
/// Put one above a list; it lives as long as the page.
class EntranceScope extends StatefulWidget {
  final Widget child;
  const EntranceScope({super.key, required this.child});

  @override
  State<EntranceScope> createState() => _EntranceScopeState();
}

class _EntranceScopeState extends State<EntranceScope> {
  final Set<Object> _seen = {};

  @override
  Widget build(BuildContext context) =>
      _EntranceScopeData(seen: _seen, child: widget.child);
}

class _EntranceScopeData extends InheritedWidget {
  final Set<Object> seen;
  const _EntranceScopeData({required this.seen, required super.child});

  @override
  bool updateShouldNotify(_EntranceScopeData oldWidget) => false;
}

/// Fades [child] in while it rises a few pixels, after [delay].
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  /// When set (and an [EntranceScope] is above), the entrance plays once
  /// per id for the life of the scope.
  final Object? id;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Motion.slow,
    this.offset = 12,
    this.id,
  });

  /// Item [index] of a list: a short cascade, capped so long lists finish
  /// quickly.
  factory FadeSlideIn.staggered({
    Key? key,
    required int index,
    required Widget child,
    Object? id,
  }) {
    final ms = Motion.staggerStep.inMilliseconds * index;
    return FadeSlideIn(
      key: key,
      id: id,
      delay: Duration(
          milliseconds: ms.clamp(0, Motion.staggerMax.inMilliseconds)),
      child: child,
    );
  }

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  // The delay is the first part of the same controller (no timers), so
  // nothing is left pending when the widget goes away.
  late final AnimationController _c = AnimationController(
      vsync: this, duration: widget.delay + widget.duration);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds /
          (widget.delay + widget.duration).inMicroseconds,
      1,
      curve: Motion.enter,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final scope = context.getInheritedWidgetOfExactType<_EntranceScopeData>();
    final id = widget.id;
    final alreadySeen = id != null && scope != null && !scope.seen.add(id);
    if (alreadySeen || !motionEnabled(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _t.value)),
            child: child,
          ),
        ),
      );
}

// ── Hover ───────────────────────────────────────────────────────────────────

/// Lifts [child] 2 px and gives it a soft shadow while the mouse is over it.
/// With [onTap] it also shows the click cursor and handles the tap.
class HoverLift extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final double lift;

  const HoverLift({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.onTap,
    this.lift = 2,
  });

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = _hover && motionEnabled(context);
    Widget body = AnimatedContainer(
      duration: motionDuration(context, Motion.fast),
      curve: Motion.enter,
      transform: Matrix4.translationValues(0, on ? -widget.lift : 0, 0),
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: on ? 0.14 : 0),
            blurRadius: on ? 18 : 0,
            offset: Offset(0, on ? 6 : 0),
          ),
        ],
      ),
      child: widget.child,
    );
    if (widget.onTap != null) {
      body = GestureDetector(onTap: widget.onTap, child: body);
    }
    return MouseRegion(
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: body,
    );
  }
}

// ── State changes ───────────────────────────────────────────────────────────

/// Cross-fades between states (loading, content, error). Give each state's
/// widget a key that changes only when the KIND of state changes (e.g.
/// `ValueKey('loading')`), so rebuilds of the same state do not animate.
class StateSwitcher extends StatelessWidget {
  final Widget child;
  final AlignmentGeometry alignment;

  const StateSwitcher({
    super.key,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: motionDuration(context, Motion.medium),
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: alignment,
          children: [...previous, if (current != null) current],
        ),
        child: child,
      );
}
