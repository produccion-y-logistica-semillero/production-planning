import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/shared/tutorial/tutorial_tours.dart';

/// Every element a tour lights up must exist in the app (a TutorialTarget
/// with that id, possibly built from a name or index) and every event it
/// waits for must be emitted somewhere. A renamed widget would otherwise
/// leave the user stuck on "Esperando a que aparezca en pantalla…".
void main() {
  final source = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f.readAsStringSync(),
  ].join('\n');

  // id: 'literal'  or  id: 'job${widget.index}.duplicate'  or
  // id: latest ? 'a' : 'b'  →  regular expressions.
  final declared = <String>{
    for (final m in RegExp(r"id:\s*'([^']+)'").allMatches(source)) m[1]!,
    for (final m in RegExp(r"latest \? '([^']+)' : '([^']+)'")
        .allMatches(source)) ...[m[1]!, m[2]!],
    // Ids handed to a helper as an argument (e.g. the automatic hours).
    for (final m in RegExp(r"'(job\$\{widget\.index\}\.[A-Za-z]+)'")
        .allMatches(source)) m[1]!,
  };
  final patterns = [
    for (final d in declared)
      RegExp('^${RegExp.escape(d).replaceAll(RegExp(r'\\\$\\\{[^}]*\\\}|\\\$[A-Za-z_]+'), '.+')}\$'),
  ];
  const menuRoutes = {'/machines', '/sequences', '/orders', '/manual', '/notacion'};

  bool exists(String id) {
    if (id.startsWith('menu/')) return menuRoutes.contains(id.substring(4));
    return patterns.any((p) => p.hasMatch(id));
  }

  for (final tour in kTours) {
    test('${tour.id}: every target and event exists', () {
      final missing = <String>[];
      for (final s in tour.steps) {
        for (final id in [s.target, s.waitFor]) {
          if (id != null && !exists(id)) missing.add('id $id (${s.title})');
        }
        final e = s.event;
        if (e != null && !source.contains("emit('$e')")) {
          missing.add('event $e (${s.title})');
        }
      }
      expect(missing, isEmpty);
    });
  }
}
