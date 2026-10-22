// The pure model behind the process-route editor: what saving an edited
// route inserts / updates / deletes, duplicating, and the layered layout.
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/route_draft.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/entities/task_entity.dart';

RouteNode node(int key, {int? taskId, int station = 1}) => RouteNode(
      key: key,
      taskId: taskId,
      machineTypeId: station,
      machineName: 'Estación $station',
    );

void main() {
  test('editing keeps, adds and removes the right tasks', () {
    // Saved route: tasks 10, 11, 12. The user removed 11 and added a node.
    final draft = RouteDraft(
      sequenceId: 1,
      name: 'Ruta',
      nodes: [
        node(10, taskId: 10, station: 1),
        node(12, taskId: 12, station: 3),
        node(-1, station: 4),
      ],
    );

    final diff = diffRoute([10, 11, 12], draft);

    expect(diff.toUpdate.map((n) => n.taskId), [10, 12]);
    expect(diff.toInsert.map((n) => n.key), [-1]);
    expect(diff.toDelete, [11]);
  });

  test('a route loaded from the database keys its nodes by task id', () {
    final sequence = SequenceEntity(
      7,
      [
        TaskEntity(
            id: 21,
            processingUnits: const Duration(minutes: 90),
            description: 'Mezclar',
            machineTypeId: 1,
            machineName: 'Mezcladora',
            allowPreemption: true),
        TaskEntity(
            id: 22,
            processingUnits: const Duration(hours: 1),
            description: '',
            machineTypeId: 2,
            machineName: 'Horno'),
      ],
      'Pan',
      [
        TaskDependencyEntity(
            predecessor_id: 21, successor_id: 22, sequenceId: 7)
      ],
    );

    final draft = RouteDraft.fromSequence(sequence);

    expect(draft.sequenceId, 7);
    expect(draft.nodes.map((n) => n.key), [21, 22]);
    expect(draft.nodes.first.processing, const Duration(minutes: 90));
    expect(draft.nodes.first.allowPreemption, isTrue);
    expect(draft.arrows, [const RouteArrow(21, 22)]);
  });

  test('a duplicate has no ids and its arrows follow the new keys', () {
    final original = RouteDraft(
      sequenceId: 7,
      name: 'Pan',
      nodes: [
        node(21, taskId: 21, station: 1),
        node(22, taskId: 22, station: 2)
      ],
      arrows: const [RouteArrow(21, 22)],
    );

    final copy = original.duplicate();

    expect(copy.sequenceId, isNull);
    expect(copy.name, 'Pan (copia)');
    expect(copy.nodes.every((n) => n.taskId == null), isTrue);
    expect(copy.nodes.every((n) => n.key < 0), isTrue);
    expect(
        copy.arrows.single, RouteArrow(copy.nodes[0].key, copy.nodes[1].key));
    // Saving the copy inserts everything and deletes nothing.
    final diff = diffRoute(const [21, 22], copy);
    expect(diff.toInsert, hasLength(2));
    expect(diff.toDelete, [21, 22]);
  });

  group('Ordenar (layered layout)', () {
    test('every arrow points to the right', () {
      // A and B enable C; C enables D.
      final positions = layeredLayout(
        [1, 2, 3, 4],
        const [RouteArrow(1, 3), RouteArrow(2, 3), RouteArrow(3, 4)],
      ).positions;

      expect(positions[1]!.dx, positions[2]!.dx);
      expect(positions[1]!.dy, isNot(positions[2]!.dy));
      expect(positions[3]!.dx, greaterThan(positions[1]!.dx));
      expect(positions[4]!.dx, greaterThan(positions[3]!.dx));
    });

    test('creation order does not cause crossings', () {
      // A → C and B → D, but the stations were created A, B, D, C: keeping
      // creation order in the second column would cross the two arrows.
      final layout = layeredLayout(
        [1, 2, 4, 3],
        const [RouteArrow(1, 3), RouteArrow(2, 4)],
      );

      expect(layout.crossings, 0);
      final p = layout.positions;
      expect((p[1]!.dy < p[2]!.dy) == (p[3]!.dy < p[4]!.dy), isTrue,
          reason: 'C must sit on the same side as A, D as B');
    });

    test('an arrow that skips a column goes around, not through, a station',
        () {
      // A → B → C plus A → C.
      final layout = layeredLayout(
        [1, 2, 3],
        const [RouteArrow(1, 2), RouteArrow(2, 3), RouteArrow(1, 3)],
      );

      expect(layout.crossings, 0);
      final bend = layout.bends[const RouteArrow(1, 3)]!.single;
      final b = layout.positions[2]!;
      // The waypoint is in B's column but not inside B.
      expect(bend.dx, closeTo(b.dx + 75, 1e-6));
      expect((bend.dy - (b.dy + 32)).abs(), greaterThan(32));
    });

    test('crossings that are unavoidable are kept to the minimum', () {
      // Three stations each feeding the same three: K3,3 between two
      // columns needs C(3,2)·C(3,2) = 9 crossings, and no fewer.
      final layout = layeredLayout(
        [1, 2, 3, 4, 5, 6],
        [
          for (final a in [1, 2, 3])
            for (final b in [4, 5, 6]) RouteArrow(a, b),
        ],
      );
      expect(layout.crossings, 9);
    });

    test(
        'a large route (heuristic search) is still laid out without '
        'crossings', () {
      // One source feeding 10 branches of two stations each, created with
      // the second stations in reverse order: 10! orderings per column is
      // past the exhaustive limit.
      final keys = <int>[0];
      final arrows = <RouteArrow>[];
      for (int i = 1; i <= 10; i++) {
        keys.add(i);
        arrows.add(RouteArrow(0, i));
      }
      for (int i = 10; i >= 1; i--) {
        keys.add(100 + i);
        arrows.add(RouteArrow(i, 100 + i));
      }

      expect(layeredLayout(keys, arrows).crossings, 0);
    });
  });
}
