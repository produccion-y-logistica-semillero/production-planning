import 'package:flutter/material.dart';
import 'package:production_planning/entities/metrics.dart';

class MetricsPage extends StatelessWidget {
  final Metrics metrics;

  MetricsPage({
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Container(
        width: 500,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Metricas',
              ),
              SizedBox(height: 20),
              _buildMetricRow('Tiempo muerto', _formatDuration(metrics.idle)),
              _buildMetricRow('Total trabajos', metrics.totalJobs.toString()),
              _buildMetricRow('Tardanza maxima', _formatDuration(metrics.maxDelay)),
              _buildMetricRow('Flujo promedio', _formatDuration(metrics.avarageProcessingTime)),
              _buildMetricRow('Tardanza promedio', _formatDuration(metrics.avarageDelayTime)),
              _buildMetricRow('Retardo promedio', _formatDuration(metrics.avarageLatenessTime)),
              _buildMetricRow('Trabajos retrasados', metrics.delayedJobs.toString()),
              _buildMetricRow('Porcentaje trabajos retrasados', '${metrics.percentageDelayedJobs.toStringAsFixed(2)}%'),
              SizedBox(height: 20),
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
          Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m ${duration.inSeconds.remainder(60)}s';
  }
}