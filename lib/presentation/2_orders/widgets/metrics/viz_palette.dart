// Colors of the metrics table and dashboard. Values come from the dataviz
// reference palette (validated for color-vision deficiency); each has its
// own step for dark mode instead of an automatic flip.
//
//  * One series (one metric across algorithms) -> one hue: blue.
//  * Best / worst -> the reserved status colors good / critical, always
//    with an icon and a label, never color alone.
//  * Rank map -> a single-hue sequential blue ramp (ordinal steps 250..650:
//    the lightest still clears 2:1 against the surface).

import 'package:flutter/material.dart';

class VizPalette {
  final bool dark;
  const VizPalette(this.dark);

  factory VizPalette.of(BuildContext context) =>
      VizPalette(Theme.of(context).brightness == Brightness.dark);

  Color get series => dark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);

  /// Status: good / critical (mode-invariant hexes).
  Color get good => const Color(0xFF0CA30C);
  Color get critical => const Color(0xFFD03B3B);

  /// Text for a good value: darker green on light, status green on dark.
  Color get goodText =>
      dark ? const Color(0xFF0CA30C) : const Color(0xFF006300);
  Color get criticalText => const Color(0xFFD03B3B);

  /// Soft wash behind a best / worst cell.
  Color get goodWash => good.withValues(alpha: dark ? 0.22 : 0.12);
  Color get criticalWash => critical.withValues(alpha: dark ? 0.22 : 0.10);

  Color get gridline =>
      dark ? const Color(0xFF2C2C2A) : const Color(0xFFE1E0D9);
  Color get track => dark ? const Color(0xFF2C2C2A) : const Color(0xFFF0EFEC);

  /// Ordinal blue ramp from weak (index 0) to strong (last).
  static const List<Color> _ramp = [
    Color(0xFF86B6EF), // 250
    Color(0xFF5598E7), // 350
    Color(0xFF2A78D6), // 450
    Color(0xFF1C5CAB), // 550
    Color(0xFF104281), // 650
  ];

  /// Color for rank [rank] (1 = best) among [count]: the best is strongest.
  Color rankColor(int rank, int count) {
    if (count <= 1) return _ramp.last;
    final t = (count - rank) / (count - 1); // 1 for the best, 0 for the worst
    return _ramp[(t * (_ramp.length - 1)).round()];
  }

  /// Ink readable on [rankColor].
  Color rankInk(int rank, int count) {
    final c = rankColor(rank, count);
    return c.computeLuminance() > 0.35 ? const Color(0xFF0B0B0B) : Colors.white;
  }
}
