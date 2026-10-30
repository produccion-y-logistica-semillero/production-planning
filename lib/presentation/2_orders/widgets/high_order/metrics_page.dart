import 'package:flutter/material.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/tabu_stats_card.dart';

class MetricsPage extends StatelessWidget {
  final Metrics metrics;


  const MetricsPage({
    super.key,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: SizedBox(
        width: 500,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Metricas',
              ),
              const SizedBox(height: 20),
              _buildMetricRow('Tiempo muerto', _formatDuration(metrics.idle)),
              _buildMetricRow('Total trabajos', metrics.totalJobs.toString()),

              _buildMetricRow(
                  'Tardanza máxima', _formatDuration(metrics.maxTardiness)),
              _buildMetricRow('Flujo promedio',
                  _formatDuration(metrics.avarageProcessingTime)),
              _buildMetricRow('Tardanza promedio',
                  _formatDuration(metrics.avarageDelayTime)),
              _buildMetricRow('Adelanto promedio',
                  _formatDuration(metrics.avarageEarlinessTime)),
              _buildMetricRow('Tardanza total',
                  _formatDuration(metrics.totalTardiness)),
              _buildMetricRow('Retardo ponderado',
                  _formatDuration(metrics.totalWeightedTardiness)),
              _buildMetricRow(
                  'Trabajos retrasados', metrics.delayedJobs.toString()),
              _buildMetricRow('Porcentaje trabajos retrasados',
                  '${metrics.percentageDelayedJobs.toStringAsFixed(2)}%'),
              // Short summary of the per-machine and per-station breakdown;
              // the full tables are in "Detalle de programación".
              if (metrics.machineUsage.isNotEmpty)
                () {
                  final m = metrics.machineUsage
                      .reduce((a, b) => b.idle > a.idle ? b : a);
                  return _buildMetricRow('Máquina más ociosa',
                      '${m.machineName} (${m.stationName}): ${_formatDuration(m.idle)}');
                }(),
              if (metrics.stationTardiness
                  .any((s) => s.totalTardiness > Duration.zero))
                () {
                  final s = metrics.stationTardiness.reduce(
                      (a, b) => b.totalTardiness > a.totalTardiness ? b : a);
                  return _buildMetricRow('Estación con más tardanza',
                      '${s.stationName}: ${_formatDuration(s.totalTardiness)}');
                }(),

              if (metrics.tabuStats != null) ...[
                const SizedBox(height: 12),
                TabuStatsCard(stats: metrics.tabuStats!),
              ],

              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          )
          ),
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final d = duration.isNegative ? duration.abs() : duration;
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
  }
  }

