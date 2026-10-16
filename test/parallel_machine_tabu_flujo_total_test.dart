// ¿Es TABU el mejor minimizando el FLUJO TOTAL (Σ (C_j − r_j)) en máquinas
// en paralelo?
//
// Para cada escenario se corre TABU y todas las reglas de despacho "puras"
// (las *_ADAPTADO se omiten porque dependen de DateTime.now()) y se compara
// el flujo total resultante.
//
// Criterio:
//   • En TODO escenario  ->  flujo(TABU) <= min(flujo de cada regla).
//     (TABU nunca debe empeorar respecto a la mejor regla.)
//   • En los escenarios con setup dependiente de secuencia, donde las reglas
//     intercalan familias y pagan cambios de preparación evitables, TABU
//     debe ser ESTRICTAMENTE mejor.
//   • En máquinas idénticas sin setup ni fechas de liberación, SPT + regla
//     de menor tiempo de fin ya es óptimo para P||ΣC_j, así que TABU debe
//     EMPATAR (no se le exige mejora).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/services/algorithms/parallel_machine.dart';

const _workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));
final _start = DateTime(2026, 1, 5, 6, 0);

// Reglas de despacho deterministas (sin dependencia de la hora actual).
const _rules = ['SPT', 'LPT', 'EDD', 'FIFO', 'WSPT', 'CR', 'ATCS', 'MS'];

class _Scenario {
  final String name;
  final List<ParallelInput> Function() buildJobs;
  final List<int> machineIds;
  final Map<int, Map<String, Map<String, int>>>? setupMatrix;

  /// Si true, se exige que TABU MEJORE a la mejor regla, no solo la iguale.
  final bool expectStrictlyBetter;

  _Scenario(
    this.name,
    this.buildJobs,
    this.machineIds, {
    this.setupMatrix,
    this.expectStrictlyBetter = false,
  });
}

int _totalFlowMinutes(List<ParallelOutput> out, List<ParallelInput> jobs) {
  final avail = {for (final j in jobs) j.jobId: j.availableDate};
  return out.fold(
    0,
    (s, o) => s + o.endDate.difference(avail[o.jobId]!).inMinutes,
  );
}

List<ParallelOutput> _run(_Scenario sc, String rule) => ParallelMachine(
      _start,
      _workingSchedule,
      sc.buildJobs(),
      {for (final m in sc.machineIds) m: <Tuple2<DateTime, DateTime>>[]},
      rule,
      stateSetupMatrix: sc.setupMatrix,
    ).output;

/// Matriz de setup uniforme: cualquier cambio de familia cuesta [minutes]
/// minutos en cualquier máquina; repetir familia, 0.
Map<int, Map<String, Map<String, int>>> _uniformSetup(
  List<int> machineIds,
  List<String> families,
  int minutes,
) =>
    {
      for (final m in machineIds)
        m: {
          for (final f in families)
            f: {
              for (final g in families)
                if (g != f) g: minutes,
            },
        },
    };

List<ParallelInput> _families({
  required List<String> pattern,
  required List<int> machineIds,
  required int processMinutes,
}) =>
    [
      for (int k = 0; k < pattern.length; k++)
        ParallelInput(
          k + 1,
          // Due date creciente en el orden dado => EDD reproduce ese orden.
          DateTime(2026, 1, 7, 0, k + 1),
          1,
          _start,
          {for (final m in machineIds) m: Duration(minutes: processMinutes)},
          jobState: pattern[k],
        ),
    ];

final List<_Scenario> _scenarios = [
  // ── S1 · 3 familias, 2 máquinas, setup 90 ──────────────────────────────
  // Patrón intercalado A,B,C,A,B,C,A,B,C. Las reglas alternan familias y
  // pagan ~90 min de setup en casi cada trabajo; TABU agrupa familias.
  _Scenario(
    'S1 · 3 familias · 2 máquinas · setup 90 · proc 20',
    () => _families(
      pattern: const ['A', 'B', 'C', 'A', 'B', 'C', 'A', 'B', 'C'],
      machineIds: const [1, 2],
      processMinutes: 20,
    ),
    const [1, 2],
    setupMatrix: _uniformSetup(const [1, 2], const ['A', 'B', 'C'], 90),
    expectStrictlyBetter: true,
  ),

  // ── S2 · 4 familias, 2 máquinas, setup 120 (caso más grande) ───────────
  _Scenario(
    'S2 · 4 familias · 2 máquinas · setup 120 · proc 15',
    () => _families(
      pattern: const [
        'A', 'B', 'C', 'D', 'A', 'B', 'C', 'D', 'A', 'B', 'C', 'D' //
      ],
      machineIds: const [1, 2],
      processMinutes: 15,
    ),
    const [1, 2],
    setupMatrix:
        _uniformSetup(const [1, 2], const ['A', 'B', 'C', 'D'], 120),
    expectStrictlyBetter: true,
  ),

  // ── S3 · 4 familias, 3 máquinas, setup 75 ──────────────────────────────
  // Hay más familias que máquinas: al menos una máquina debe procesar 2
  // familias, así que el ORDEN y el reparto importan. Las reglas intercalan;
  // TABU consolida (p. ej. A+D en una máquina, B y C en las otras).
  _Scenario(
    'S3 · 4 familias · 3 máquinas · setup 75 · proc 20',
    () => _families(
      pattern: const [
        'A', 'B', 'C', 'D', 'A', 'B', 'C', 'D', 'A', 'B', 'C', 'D' //
      ],
      machineIds: const [1, 2, 3],
      processMinutes: 20,
    ),
    const [1, 2, 3],
    setupMatrix:
        _uniformSetup(const [1, 2, 3], const ['A', 'B', 'C', 'D'], 75),
    expectStrictlyBetter: true,
  ),

  // ── S4 · máquinas idénticas, SIN setup ni releases ────────────────────
  // SPT + fin más temprano ya es óptimo para P||ΣC_j: TABU debe EMPATAR.
  _Scenario(
    'S4 · 2 máquinas idénticas · sin setup · 10 trabajos',
    () {
      const proc = [30, 45, 12, 60, 25, 18, 50, 40, 22, 35];
      return [
        for (int k = 0; k < proc.length; k++)
          ParallelInput(
            k + 1,
            DateTime(2026, 1, 7, 0, k + 1),
            1,
            _start,
            {
              1: Duration(minutes: proc[k]),
              2: Duration(minutes: proc[k]),
            },
          ),
      ];
    },
    const [1, 2],
  ),

  // ── S5 · 3 familias, 3 máquinas, setup 75 (empate) ────────────────────
  // #familias == #máquinas: la asignación greedy ya coloca cada familia en
  // su propia máquina (óptimo, sin setups). TABU debe IGUALAR, no regresar.
  _Scenario(
    'S5 · 3 familias · 3 máquinas · setup 75 (reglas ya óptimas)',
    () => _families(
      pattern: const [
        'A', 'B', 'C', 'A', 'B', 'C', 'A', 'B', 'C', 'A', 'B', 'C' //
      ],
      machineIds: const [1, 2, 3],
      processMinutes: 20,
    ),
    const [1, 2, 3],
    setupMatrix: _uniformSetup(const [1, 2, 3], const ['A', 'B', 'C'], 75),
  ),
];

void main() {
  final summary = <String>[];

  for (final sc in _scenarios) {
    test(sc.name, () {
      final jobsRef = sc.buildJobs();

      final ruleFlows = <String, int>{};
      for (final r in _rules) {
        ruleFlows[r] = _totalFlowMinutes(_run(sc, r), jobsRef);
      }
      final tabuFlow = _totalFlowMinutes(_run(sc, 'TABU'), jobsRef);

      final bestRule = ruleFlows.values.reduce((a, b) => a < b ? a : b);
      final bestRuleName =
          ruleFlows.entries.firstWhere((e) => e.value == bestRule).key;

      final line = '${sc.name}\n'
          '    reglas: ${ruleFlows.entries.map((e) => '${e.key}=${e.value}').join('  ')}\n'
          '    mejor regla = $bestRuleName ($bestRule min)   |   TABU = $tabuFlow min'
          '${sc.expectStrictlyBetter ? '   (mejora ${((bestRule - tabuFlow) * 100 / bestRule).toStringAsFixed(1)}%)' : ''}';
      summary.add(line);
      // ignore: avoid_print
      print(line);

      expect(
        tabuFlow,
        lessThanOrEqualTo(bestRule),
        reason: 'TABU no debe dar peor flujo total que la mejor regla '
            '($bestRuleName=$bestRule) en "${sc.name}"',
      );

      if (sc.expectStrictlyBetter) {
        expect(
          tabuFlow,
          lessThan(bestRule),
          reason: 'En "${sc.name}" TABU debería mejorar el flujo total '
              'agrupando familias y evitando setups',
        );
      }
    });
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('\n===== RESUMEN FLUJO TOTAL (min) =====\n${summary.join('\n')}');
  });
}
