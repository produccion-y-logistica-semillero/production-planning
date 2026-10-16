// lib/entities/route_draft.dart
//
// The process route being created or edited, independent of the canvas that
// draws it and of the database that stores it. Pure: no Flutter widgets, no
// I/O — so the save logic (what to insert, update and delete when a route is
// edited) and the auto-layout can be unit-tested.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_entity.dart';

/// Standard time a new station gets before the user sets one.
const Duration kDefaultStationTime = Duration(hours: 1);

/// One station (task) of a route.
///
/// [key] identifies the node on the canvas and in the arrows. For a task
/// that already exists in the database it is its `task_id`; for a task added
/// in the editor it is a negative number, unique within the draft.
class RouteNode {
  final int key;

  /// Database id, null until the task is saved.
  final int? taskId;
  final int machineTypeId;
  final String machineName;
  String description;

  /// Standard processing time: the default every job of this route starts
  /// from (each job can then adjust it per machine).
  Duration processing;

  /// Default for the job's "¿Se puede interrumpir?" switches.
  bool allowPreemption;

  RouteNode({
    required this.key,
    this.taskId,
    required this.machineTypeId,
    required this.machineName,
    this.description = '',
    this.processing = kDefaultStationTime,
    this.allowPreemption = false,
  });

  RouteNode copy({int? key, bool keepTaskId = true}) => RouteNode(
        key: key ?? this.key,
        taskId: keepTaskId ? taskId : null,
        machineTypeId: machineTypeId,
        machineName: machineName,
        description: description,
        processing: processing,
        allowPreemption: allowPreemption,
      );

  /// The station as the canvas palette knows it.
  MachineTypeEntity get station => MachineTypeEntity(
      id: machineTypeId, name: machineName, description: description);
}

/// A directed arrow between two nodes, by [RouteNode.key].
class RouteArrow {
  final int from;
  final int to;
  const RouteArrow(this.from, this.to);

  @override
  bool operator ==(Object other) =>
      other is RouteArrow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class RouteDraft {
  /// Null for a route that is not saved yet.
  final int? sequenceId;
  final String name;
  final List<RouteNode> nodes;
  final List<RouteArrow> arrows;

  const RouteDraft({
    this.sequenceId,
    required this.name,
    this.nodes = const [],
    this.arrows = const [],
  });

  /// A route loaded from the database: node key = task id.
  factory RouteDraft.fromSequence(SequenceEntity sequence) {
    final nodes = <RouteNode>[
      for (final TaskEntity t in sequence.tasks ?? const <TaskEntity>[])
        if (t.id != null)
          RouteNode(
            key: t.id!,
            taskId: t.id,
            machineTypeId: t.machineTypeId,
            machineName: t.machineName ?? '',
            description: t.description,
            processing: t.processingUnits,
            allowPreemption: t.allowPreemption,
          ),
    ];
    final keys = nodes.map((n) => n.key).toSet();
    final arrows = <RouteArrow>[
      for (final d in sequence.dependencies ?? const [])
        if (keys.contains(d.predecessor_id) && keys.contains(d.successor_id))
          RouteArrow(d.predecessor_id, d.successor_id),
    ];
    return RouteDraft(
      sequenceId: sequence.id,
      name: sequence.name,
      nodes: nodes,
      arrows: arrows,
    );
  }

  /// A copy saved as a NEW route: no ids, every node and arrow re-keyed.
  RouteDraft duplicate() {
    final Map<int, int> newKey = {};
    int next = -1;
    final nodes = <RouteNode>[];
    for (final n in this.nodes) {
      newKey[n.key] = next;
      nodes.add(n.copy(key: next, keepTaskId: false));
      next--;
    }
    return RouteDraft(
      name: '$name (copia)',
      nodes: nodes,
      arrows: [
        for (final a in arrows) RouteArrow(newKey[a.from]!, newKey[a.to]!),
      ],
    );
  }

  RouteDraft copyWith({String? name, int? sequenceId}) => RouteDraft(
        sequenceId: sequenceId ?? this.sequenceId,
        name: name ?? this.name,
        nodes: nodes,
        arrows: arrows,
      );
}

/// What saving [draft] over a route whose tasks are [existingTaskIds] does.
class RouteDiff {
  /// Nodes to insert as new tasks.
  final List<RouteNode> toInsert;

  /// Nodes whose task already exists: updated in place, keeping their id.
  final List<RouteNode> toUpdate;

  /// Task ids that are no longer in the route.
  final List<int> toDelete;

  const RouteDiff(this.toInsert, this.toUpdate, this.toDelete);
}

RouteDiff diffRoute(Iterable<int> existingTaskIds, RouteDraft draft) {
  final existing = existingTaskIds.toSet();
  final insert = <RouteNode>[];
  final update = <RouteNode>[];
  final kept = <int>{};
  for (final n in draft.nodes) {
    final id = n.taskId;
    if (id != null && existing.contains(id)) {
      update.add(n);
      kept.add(id);
    } else {
      insert.add(n);
    }
  }
  return RouteDiff(
    insert,
    update,
    [for (final id in existing) if (!kept.contains(id)) id],
  );
}

/// Result of [layeredLayout].
class RouteLayout {
  /// Top-left corner of every node.
  final Map<int, Offset> positions;

  /// Intermediate points of the arrows that skip columns: the arrow is drawn
  /// as a polyline through them, so it never runs across another node.
  final Map<RouteArrow, List<Offset>> bends;

  /// Arrow crossings left in the layout (0 unless unavoidable; see
  /// [layeredLayout]).
  final int crossings;

  const RouteLayout(this.positions, this.bends, this.crossings);
}

/// Above this many candidate orderings the search switches from exhaustive
/// to heuristic.
const int _exhaustiveLimit = 200000;

/// Lays the route out in columns by precedence with as few arrow crossings
/// as possible (Sugiyama, Tagawa & Toda, 1981):
///
///  1. Columns. A node's column is the length of the longest arrow path
///     reaching it, so every arrow points to the right.
///  2. Long arrows. An arrow that skips columns gets one invisible waypoint
///     per skipped column and is drawn through them ([RouteLayout.bends]),
///     so it never runs across another node.
///  3. Order within each column. Chosen to minimise crossings between
///     neighbouring columns, then to keep arrows as straight as possible.
///     When the number of possible orderings is small (every realistic
///     process route) ALL of them are tried, so the result has zero
///     crossings whenever a crossing-free layout exists. Larger graphs use
///     the barycenter heuristic with adjacent swaps, which almost always
///     reaches the minimum but cannot prove it.
///
/// The order the nodes were created in only breaks ties. Arrows that would
/// close a cycle are ignored (the editor never allows them).
RouteLayout layeredLayout(
  List<int> nodeKeys,
  List<RouteArrow> arrows, {
  Offset origin = const Offset(60, 60),
  double dx = 230,
  double dy = 110,
  double nodeWidth = 150,
  double nodeHeight = 64,
}) {
  if (nodeKeys.isEmpty) return const RouteLayout({}, {}, 0);
  final keys = nodeKeys.toSet();
  final validArrows = <RouteArrow>[
    for (final a in arrows.toSet())
      if (keys.contains(a.from) && keys.contains(a.to) && a.from != a.to) a,
  ];

  // 1. Columns (longest path).
  final preds = <int, List<int>>{for (final k in nodeKeys) k: []};
  for (final a in validArrows) {
    preds[a.to]!.add(a.from);
  }
  final level = <int, int>{};
  final visiting = <int>{};
  int levelOf(int k) {
    final known = level[k];
    if (known != null) return known;
    if (!visiting.add(k)) return 0; // cycle guard
    int l = 0;
    for (final p in preds[k]!) {
      l = math.max(l, levelOf(p) + 1);
    }
    visiting.remove(k);
    return level[k] = l;
  }

  for (final k in nodeKeys) {
    levelOf(k);
  }

  // 2. Vertices per column, with waypoints for long arrows. Vertex ids:
  // 0..n-1 are the real nodes (creation order), n.. are waypoints.
  final int n = nodeKeys.length;
  final indexOf = {for (int i = 0; i < n; i++) nodeKeys[i]: i};
  final vertexLevel = <int>[for (final k in nodeKeys) level[k]!];
  final segments = <(int, int)>[]; // always between adjacent columns
  final chainOf = <RouteArrow, List<int>>{};
  for (final a in validArrows) {
    final from = indexOf[a.from]!, to = indexOf[a.to]!;
    if (vertexLevel[to] <= vertexLevel[from]) continue; // part of a cycle
    int prev = from;
    final chain = <int>[];
    for (int l = vertexLevel[from] + 1; l < vertexLevel[to]; l++) {
      final v = vertexLevel.length;
      vertexLevel.add(l);
      chain.add(v);
      segments.add((prev, v));
      prev = v;
    }
    segments.add((prev, to));
    chainOf[a] = chain;
  }

  final int columns = vertexLevel.reduce(math.max) + 1;
  final layers = List.generate(columns, (_) => <int>[]);
  for (int v = 0; v < vertexLevel.length; v++) {
    layers[vertexLevel[v]].add(v);
  }
  final segmentsFrom = List.generate(columns, (_) => <(int, int)>[]);
  for (final s in segments) {
    segmentsFrom[vertexLevel[s.$1]].add(s);
  }

  // 3. Order within columns.
  final pos = List<int>.filled(vertexLevel.length, 0);
  void index(List<List<int>> order) {
    for (final layer in order) {
      for (int i = 0; i < layer.length; i++) {
        pos[layer[i]] = i;
      }
    }
  }

  int crossingsBetween(int column) {
    final segs = segmentsFrom[column];
    int c = 0;
    for (int i = 0; i < segs.length; i++) {
      for (int j = i + 1; j < segs.length; j++) {
        final a = pos[segs[i].$1] - pos[segs[j].$1];
        final b = pos[segs[i].$2] - pos[segs[j].$2];
        if (a * b < 0) c++;
      }
    }
    return c;
  }

  // Vertical offset of a vertex from its column's centre line, in slots.
  double slot(int v) => pos[v] - (layers[vertexLevel[v]].length - 1) / 2.0;

  (int, double) score(List<List<int>> order) {
    index(order);
    int c = 0;
    double bend = 0;
    for (int l = 0; l < columns - 1; l++) {
      c += crossingsBetween(l);
      for (final s in segmentsFrom[l]) {
        bend += (slot(s.$1) - slot(s.$2)).abs();
      }
    }
    return (c, bend);
  }

  bool better((int, double) a, (int, double) b) =>
      a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 < b.$2 - 1e-9);

  int combinations = 1;
  outer:
  for (final layer in layers) {
    for (int k = 2; k <= layer.length; k++) {
      combinations *= k;
      if (combinations > _exhaustiveLimit) break outer;
    }
  }

  List<List<int>> best = [for (final l in layers) List.of(l)];
  var bestScore = score(best);

  if (combinations <= _exhaustiveLimit) {
    // Exhaustive, column by column, pruning on the crossings already fixed
    // (those between columns l-1 and l are known once both are placed).
    final current = [for (final l in layers) List.of(l)];
    void search(int column, int crossingsSoFar) {
      if (crossingsSoFar > bestScore.$1) return;
      if (column == columns) {
        final s = score(current);
        if (better(s, bestScore)) {
          bestScore = s;
          best = [for (final l in current) List.of(l)];
        }
        return;
      }
      for (final perm in _permutations(layers[column])) {
        current[column] = perm;
        int c = crossingsSoFar;
        if (column > 0) {
          index(current);
          c += crossingsBetween(column - 1);
        }
        search(column + 1, c);
      }
      current[column] = List.of(layers[column]);
    }

    search(0, 0);
  } else {
    // Barycenter sweeps with adjacent swaps (transpose); keep the best.
    final order = [for (final l in layers) List.of(l)];
    final succ = <int, List<int>>{};
    final pred = <int, List<int>>{};
    for (final s in segments) {
      succ.putIfAbsent(s.$1, () => []).add(s.$2);
      pred.putIfAbsent(s.$2, () => []).add(s.$1);
    }
    void sortByBarycenter(int column, Map<int, List<int>> neighbours) {
      index(order);
      final layer = order[column];
      final bary = <int, double>{
        for (final v in layer)
          v: (neighbours[v] == null || neighbours[v]!.isEmpty)
              ? pos[v].toDouble()
              : neighbours[v]!.map((u) => pos[u]).reduce((a, b) => a + b) /
                  neighbours[v]!.length,
      };
      layer.sort((a, b) {
        final c = bary[a]!.compareTo(bary[b]!);
        return c != 0 ? c : pos[a].compareTo(pos[b]);
      });
    }

    for (int iter = 0; iter < 24; iter++) {
      if (iter.isEven) {
        for (int l = 1; l < columns; l++) {
          sortByBarycenter(l, pred);
        }
      } else {
        for (int l = columns - 2; l >= 0; l--) {
          sortByBarycenter(l, succ);
        }
      }
      bool improved = true;
      while (improved) {
        improved = false;
        for (final layer in order) {
          for (int i = 0; i + 1 < layer.length; i++) {
            final before = score(order);
            final t = layer[i];
            layer[i] = layer[i + 1];
            layer[i + 1] = t;
            if (better(score(order), before)) {
              improved = true;
            } else {
              layer[i + 1] = layer[i];
              layer[i] = t;
            }
          }
        }
      }
      final s = score(order);
      if (better(s, bestScore)) {
        bestScore = s;
        best = [for (final l in order) List.of(l)];
      }
    }
  }

  // 4. Coordinates.
  index(best);
  double minSlot = 0;
  for (int v = 0; v < vertexLevel.length; v++) {
    minSlot = math.min(minSlot, slot(v));
  }
  Offset centre(int v) => Offset(
        origin.dx + vertexLevel[v] * dx + nodeWidth / 2,
        origin.dy + (slot(v) - minSlot) * dy + nodeHeight / 2,
      );

  return RouteLayout(
    {
      for (int i = 0; i < n; i++)
        nodeKeys[i]: centre(i) - Offset(nodeWidth / 2, nodeHeight / 2),
    },
    {
      for (final e in chainOf.entries)
        if (e.value.isNotEmpty) e.key: [for (final v in e.value) centre(v)],
    },
    bestScore.$1,
  );
}

/// All orderings of [items], starting with [items] itself.
Iterable<List<int>> _permutations(List<int> items) sync* {
  if (items.length <= 1) {
    yield List.of(items);
    return;
  }
  for (int i = 0; i < items.length; i++) {
    final rest = [...items.sublist(0, i), ...items.sublist(i + 1)];
    for (final p in _permutations(rest)) {
      yield [items[i], ...p];
    }
  }
}
