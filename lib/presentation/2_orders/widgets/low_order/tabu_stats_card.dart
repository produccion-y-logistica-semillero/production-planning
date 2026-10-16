import 'package:flutter/material.dart';
import 'package:production_planning/entities/tabu_run_stats.dart';

/// Tarjeta con el resumen de una corrida de la busqueda tabu: iteraciones,
/// tiempo y flujo total. Si la busqueda se detuvo por el limite de tiempo
/// (no por iteraciones) lo avisa, porque ahi el tiempo es el cuello de
/// botella y el resultado podria mejorar con mas presupuesto.
class TabuStatsCard extends StatelessWidget {
  final TabuRunStats stats;

  const TabuStatsCard({super.key, required this.stats});

  String _seconds(int ms) => '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';

  String _percent(double value) =>
      '${value.toStringAsFixed(1).replaceAll('.', ',')} %';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool byTime = stats.stoppedByTime;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Busqueda tabu',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _row('Iteraciones', '${stats.iterations} / ${stats.maxIterations}'),
            _row('Tiempo',
                '${_seconds(stats.elapsedMs)} / ${_seconds(stats.timeBudgetMs)}'),
            _row('Tiempo por iteracion', _seconds(stats.msPerIteration)),
            _row(
              'Flujo total',
              '${stats.initialFlowMinutes} → ${stats.bestFlowMinutes} min '
                  '(${_percent(stats.improvementPercent)})',
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: byTime
                    ? colorScheme.tertiaryContainer
                    : colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    byTime ? Icons.timer_outlined : Icons.check_circle_outline,
                    size: 18,
                    color: byTime
                        ? colorScheme.onTertiaryContainer
                        : colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      byTime
                          ? 'Se detuvo por el limite de tiempo, no por '
                              'iteraciones: la busqueda pudo seguir mejorando. '
                              'Sube el presupuesto de tiempo para probarlo.'
                          : 'Completo todas las iteraciones antes de agotar '
                              'el tiempo.',
                      style: TextStyle(
                        fontSize: 12,
                        color: byTime
                            ? colorScheme.onTertiaryContainer
                            : colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}