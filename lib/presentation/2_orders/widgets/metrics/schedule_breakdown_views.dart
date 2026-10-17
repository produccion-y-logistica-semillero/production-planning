import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/metrics_breakdown.dart';
import 'package:production_planning/shared/duration_format.dart';

String _pct(double v) =>
    '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')} %';

String _d(Duration d) => formatDuration(d);

Widget _section(BuildContext context, String title, String subtitle) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}

Widget _table(BuildContext context, List<String> columns,
    List<List<String>> rows, {Set<int> numeric = const {}, int? highlightRow}) {
  final cs = Theme.of(context).colorScheme;
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      headingRowColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
      columns: [
        for (int i = 0; i < columns.length; i++)
          DataColumn(label: Text(columns[i]), numeric: numeric.contains(i)),
      ],
      rows: [
        for (int r = 0; r < rows.length; r++)
          DataRow(
            color: r == highlightRow
                ? WidgetStatePropertyAll(
                    cs.errorContainer.withValues(alpha: 0.35))
                : null,
            cells: [for (final c in rows[r]) DataCell(Text(c))],
          ),
      ],
    ),
  );
}

/// Idle time per machine and per station.
class MachineIdleView extends StatelessWidget {
  final Metrics metrics;
  const MachineIdleView({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final machines = [...metrics.machineUsage]
      ..sort((a, b) {
        final c = a.stationName.compareTo(b.stationName);
        return c != 0 ? c : a.machineName.compareTo(b.machineName);
      });
    if (machines.isEmpty) {
      return const Center(child: Text('No hay datos de máquinas.'));
    }
    final stations = [...metrics.stationUsage]
      ..sort((a, b) => b.idle.compareTo(a.idle));
    final mostIdle = machines.reduce((a, b) => b.idle > a.idle ? b : a);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(
            context,
            'Por máquina',
            'Horizonte: del primer inicio al último fin del programa. Ocio = '
                'tiempo disponible sin trabajo. "No disponible" es fuera de '
                'turno o en mantenimiento; "Descanso" son las pausas por uso '
                'continuo dentro de una operación.',
          ),
          _table(
            context,
            const [
              'Estación',
              'Máquina',
              'Proceso',
              'Alistamiento',
              'Descanso',
              'No disponible',
              'Ocio',
              'Utilización',
            ],
            [
              for (final m in machines)
                [
                  m.stationName,
                  m.machineName,
                  _d(m.processing),
                  _d(m.setup),
                  _d(m.rest),
                  _d(m.unavailable),
                  _d(m.idle),
                  _pct(m.utilization),
                ],
            ],
            numeric: const {2, 3, 4, 5, 6, 7},
            highlightRow: machines.indexOf(mostIdle),
          ),
          const SizedBox(height: 24),
          _section(
            context,
            'Por estación',
            'Suma de las máquinas de cada estación, de la más ociosa a la '
                'menos ociosa.',
          ),
          _table(
            context,
            const [
              'Estación',
              'Máquinas',
              'Proceso',
              'Alistamiento',
              'Ocio total',
              'Ocio por máquina',
              'Utilización',
            ],
            [
              for (final s in stations)
                [
                  s.stationName,
                  '${s.machines}',
                  _d(s.processing),
                  _d(s.setup),
                  _d(s.idle),
                  _d(s.idlePerMachine),
                  _pct(s.utilization),
                ],
            ],
            numeric: const {1, 2, 3, 4, 5, 6},
          ),
        ],
      ),
    );
  }
}

/// Due-date compliance per job and tardiness per station.
class JobComplianceView extends StatelessWidget {
  final Metrics metrics;
  const JobComplianceView({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final jobs = [...metrics.jobDeliveries]
      ..sort((a, b) {
        final c = b.tardiness.compareTo(a.tardiness);
        return c != 0 ? c : a.jobId.compareTo(b.jobId);
      });
    if (jobs.isEmpty) {
      return const Center(child: Text('No hay datos de jobs.'));
    }
    final stations = [...metrics.stationTardiness]
      ..sort((a, b) => b.totalTardiness.compareTo(a.totalTardiness));
    final late = jobs.where((j) => j.isLate).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(
            context,
            'Por job',
            '$late de ${jobs.length} jobs terminan después de su fecha de '
                'entrega. Ordenados de mayor a menor tardanza.',
          ),
          _table(
            context,
            const [
              'Job',
              'Última estación',
              'Entrega',
              'Terminación',
              'Tardanza',
              'Adelanto',
              'Prioridad',
            ],
            [
              for (final j in jobs)
                [
                  j.jobName,
                  j.lastStation,
                  fmt.format(j.dueDate),
                  fmt.format(j.completion),
                  j.isLate ? _d(j.tardiness) : '—',
                  j.isLate ? '—' : _d(j.earliness),
                  '${j.priority}',
                ],
            ],
            numeric: const {4, 5, 6},
          ),
          const SizedBox(height: 24),
          _section(
            context,
            'Por estación',
            'Tardanza de los jobs según la estación donde terminaron: señala '
                'en qué parte de la ruta se acumula el retraso.',
          ),
          _table(
            context,
            const [
              'Estación',
              'Jobs que terminan aquí',
              'Jobs tardíos',
              'Tardanza total',
              'Tardanza máxima',
            ],
            [
              for (final StationTardiness s in stations)
                [
                  s.stationName,
                  '${s.jobs}',
                  '${s.lateJobs}',
                  _d(s.totalTardiness),
                  _d(s.maxTardiness),
                ],
            ],
            numeric: const {1, 2, 3, 4},
          ),
        ],
      ),
    );
  }
}
