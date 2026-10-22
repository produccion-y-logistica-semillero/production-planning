import 'package:flutter/material.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/tabu_params.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/tabu_stats_card.dart';
import 'package:production_planning/shared/duration_format.dart';

/// Pestaña de análisis de la búsqueda tabú en la página de métricas.
///
/// Reúne lo que el planeador necesita para juzgar una corrida de TABU:
/// cómo terminó la búsqueda ([TabuStatsCard]), con qué parámetros se corrió,
/// y cómo queda frente a las demás reglas elegidas en el criterio que
/// optimiza (flujo total), junto a dos métricas que puede sacrificar.
class TabuAnalysis extends StatelessWidget {
  final List<String> ruleNames;
  final List<Metrics> metrics;

  /// Parámetros con que se corrió la búsqueda; null = valores por defecto.
  final TabuParams? params;

  const TabuAnalysis({
    super.key,
    required this.ruleNames,
    required this.metrics,
    this.params,
  });

  static bool isTabu(String ruleName) => ruleName.toUpperCase() == 'TABU';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabuRow = ruleNames.indexWhere(isTabu);
    if (tabuRow < 0) return const SizedBox.shrink();
    final tabu = metrics[tabuRow];
    final stats = tabu.tabuStats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Análisis de la búsqueda tabú',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'La búsqueda tabú minimiza el flujo total (suma de terminación '
            'menos liberación de cada trabajo). Las demás métricas no son su '
            'objetivo y pueden empeorar.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: stats != null
                    ? TabuStatsCard(stats: stats)
                    : const _NoStatsNotice(),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _ParamsCard(params: params ?? const TabuParams()),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Comparison(ruleNames: ruleNames, metrics: metrics, tabuRow: tabuRow),
        ],
      ),
    );
  }
}

/// La regla TABU de Single Machine no registra estadísticas de la corrida;
/// solo la de máquinas paralelas lo hace.
class _NoStatsNotice extends StatelessWidget {
  const _NoStatsNotice();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Esta corrida no registró estadísticas de la búsqueda: solo '
                'la búsqueda tabú de máquinas paralelas las reporta. La '
                'comparación con las demás reglas sí está disponible abajo.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParamsCard extends StatelessWidget {
  final TabuParams params;
  const _ParamsCard({required this.params});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds =
        (params.timeBudgetMs / 1000).toStringAsFixed(1).replaceAll('.', ',');
    final rows = <(String, String)>[
      ('Iteraciones máximas', '${params.maxIterations}'),
      ('Intentos intra-máquina', '${params.intraAttempts}'),
      ('Muestra inter-máquina', '${params.interJobSamples}'),
      ('Destinos por job', '${params.maxDestinations}'),
      ('Presupuesto de tiempo', '$seconds s'),
      ('Semilla', '${params.seed}'),
      ('Arranque', params.randomStart ? 'Aleatorio' : 'Mejor semilla'),
    ];
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Parámetros usados',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(value),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tabla de las reglas elegidas ordenadas por flujo total, con la diferencia
/// de cada una frente a TABU.
class _Comparison extends StatelessWidget {
  final List<String> ruleNames;
  final List<Metrics> metrics;
  final int tabuRow;

  const _Comparison({
    required this.ruleNames,
    required this.metrics,
    required this.tabuRow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tabuFlow = metrics[tabuRow].totalFlow;

    final order = List<int>.generate(metrics.length, (i) => i)
      ..sort((a, b) {
        final c = metrics[a].totalFlow.compareTo(metrics[b].totalFlow);
        return c != 0 ? c : ruleNames[a].compareTo(ruleNames[b]);
      });
    final position = order.indexOf(tabuRow) + 1;
    final others = order.where((i) => i != tabuRow).toList();
    final bestOther = others.isEmpty ? null : others.first;

    final flowPrecision = columnPrecision(metrics.map((m) => m.totalFlow));
    final spanPrecision = columnPrecision(metrics.map((m) => m.makespan));
    final tardPrecision = columnPrecision(metrics.map((m) => m.totalTardiness));

    String verdict;
    if (bestOther == null) {
      verdict = 'Solo se eligió TABU; elige otras reglas para compararla.';
    } else {
      final diff = metrics[bestOther].totalFlow - tabuFlow;
      if (diff > Duration.zero) {
        verdict = 'TABU mejora en ${formatDuration(diff, flowPrecision)} el '
            'flujo total de la mejor otra regla (${ruleNames[bestOther]}).';
      } else if (diff == Duration.zero) {
        verdict = 'TABU empata con la mejor otra regla '
            '(${ruleNames[bestOther]}) en flujo total.';
      } else {
        verdict = 'TABU queda ${formatDuration(-diff, flowPrecision)} por '
            'encima de la mejor otra regla (${ruleNames[bestOther]}) en flujo '
            'total.';
      }
    }

    String pct(Duration d) {
      if (tabuFlow == Duration.zero) return '—';
      final p = (d.inMicroseconds - tabuFlow.inMicroseconds) *
          100 /
          tabuFlow.inMicroseconds;
      final s = p.abs().toStringAsFixed(1).replaceAll('.', ',');
      if (p == 0) return '0 %';
      return p > 0 ? '+$s %' : '−$s %';
    }

    DataCell cell(String text, bool bold) => DataCell(Text(text,
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comparación con las demás reglas elegidas',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('TABU ocupa el puesto $position de ${metrics.length} en flujo '
            'total. $verdict'),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStatePropertyAll(cs.surfaceContainerHighest),
            columns: const [
              DataColumn(label: Text('Puesto'), numeric: true),
              DataColumn(label: Text('Regla')),
              DataColumn(label: Text('Flujo total')),
              DataColumn(label: Text('Frente a TABU')),
              DataColumn(label: Text('Makespan')),
              DataColumn(label: Text('Tardanza total')),
            ],
            rows: [
              for (var k = 0; k < order.length; k++)
                DataRow(
                  color: order[k] == tabuRow
                      ? WidgetStatePropertyAll(
                          cs.primaryContainer.withValues(alpha: 0.35))
                      : null,
                  cells: [
                    cell('${k + 1}', order[k] == tabuRow),
                    cell(ruleNames[order[k]], order[k] == tabuRow),
                    cell(
                        formatDuration(
                            metrics[order[k]].totalFlow, flowPrecision),
                        order[k] == tabuRow),
                    cell(
                        order[k] == tabuRow
                            ? '—'
                            : pct(metrics[order[k]].totalFlow),
                        order[k] == tabuRow),
                    cell(
                        formatDuration(
                            metrics[order[k]].makespan, spanPrecision),
                        order[k] == tabuRow),
                    cell(
                        formatDuration(
                            metrics[order[k]].totalTardiness, tardPrecision),
                        order[k] == tabuRow),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '"Frente a TABU" es cuánto más (+) o menos (−) flujo total tiene cada '
          'regla respecto a TABU.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
