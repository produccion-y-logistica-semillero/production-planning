// The metrics compared between algorithms, shared by the table and the
// dashboard: name, explanation, how to read the value, and which way is
// better. Plus the comparisons both views need (best / worst, ranks,
// overall score). Pure: no widgets.

import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/shared/duration_format.dart';

/// Which way a metric is better.
enum MetricSense {
  /// Smaller is better (time, tardiness, late jobs, idle time).
  lowerIsBetter,

  /// Not better or worse by itself (earliness): shown, never ranked.
  neutral,
}

class MetricDef {
  final String id;

  /// Column header, may contain a line break.
  final String header;

  /// Full name, for cards, chips and tooltips.
  final String name;
  final String description;
  final MetricSense sense;

  /// Exact comparable value (microseconds for durations, a count otherwise).
  final num Function(Metrics m) value;

  /// The duration behind the value, for duration metrics; null otherwise.
  final Duration Function(Metrics m)? duration;

  /// Text for a count metric (durations are formatted per column instead).
  final String Function(Metrics m)? countText;

  const MetricDef({
    required this.id,
    required this.header,
    required this.name,
    required this.description,
    required this.sense,
    required this.value,
    this.duration,
    this.countText,
  });

  bool get ranked => sense != MetricSense.neutral;

  /// The value as text, at the column's [precision] for durations.
  String format(Metrics m, DurationPrecision precision) {
    final d = duration;
    if (d != null) return formatDuration(d(m), precision);
    return countText!(m);
  }
}

MetricDef _durationMetric(
  String id,
  String header,
  String name,
  String description,
  Duration Function(Metrics m) duration, {
  MetricSense sense = MetricSense.lowerIsBetter,
}) =>
    MetricDef(
      id: id,
      header: header,
      name: name,
      description: description,
      sense: sense,
      value: (m) => duration(m).inMicroseconds,
      duration: duration,
    );

/// The metrics, in table order.
final List<MetricDef> kMetrics = [
  _durationMetric(
    'makespan',
    'Makespan',
    'Makespan',
    'Tiempo desde que empieza el primer trabajo hasta que termina el último.',
    (m) => m.makespan,
  ),
  _durationMetric(
    'totalFlow',
    'Flujo\ntotal',
    'Flujo total',
    'Suma del tiempo que cada trabajo pasa en el sistema, desde que está '
        'disponible hasta que termina.',
    (m) => m.totalFlow,
  ),
  _durationMetric(
    'totalTardiness',
    'Tardanza\ntotal',
    'Tardanza total',
    'Suma de los retrasos de los trabajos que terminan después de su fecha '
        'de entrega.',
    (m) => m.totalTardiness,
  ),
  _durationMetric(
    'weightedTardiness',
    'Tardanza\nponderada',
    'Tardanza ponderada',
    'Tardanza total en la que cada retraso se multiplica por la prioridad '
        'del trabajo.',
    (m) => m.totalWeightedTardiness,
  ),
  _durationMetric(
    'avgTardiness',
    'Tardanza\npromedio',
    'Tardanza promedio',
    'Retraso promedio por trabajo (los que llegan a tiempo cuentan 0).',
    (m) => m.avarageDelayTime,
  ),
  MetricDef(
    id: 'delayedJobs',
    header: 'Trabajos\nretrasados',
    name: 'Trabajos retrasados',
    description: 'Cuántos trabajos terminan después de su fecha de entrega, '
        'y qué porcentaje del total son.',
    sense: MetricSense.lowerIsBetter,
    value: (m) => m.delayedJobs,
    countText: (m) =>
        '${m.delayedJobs} · ${m.percentageDelayedJobs.toStringAsFixed(0)} %',
  ),
  _durationMetric(
    'avgEarliness',
    'Adelanto\npromedio',
    'Adelanto promedio',
    'Cuánto antes de su fecha de entrega terminan los trabajos, en promedio. '
        'No se califica como mejor ni peor: terminar muy antes puede '
        'significar inventario en espera.',
    (m) => m.avarageEarlinessTime,
    sense: MetricSense.neutral,
  ),
  _durationMetric(
    'idle',
    'Ociosidad',
    'Ociosidad',
    'Tiempo total que las máquinas pasan sin trabajar dentro del programa.',
    (m) => m.idle,
  ),
];

/// The five headline objectives (dashboard cards, default overall score).
const List<String> kHeadlineMetricIds = [
  'makespan',
  'totalFlow',
  'totalTardiness',
  'weightedTardiness',
  'delayedJobs',
];

MetricDef metricById(String id) => kMetrics.firstWhere((m) => m.id == id);

/// Display precision for [metric] across all [rows].
DurationPrecision precisionFor(MetricDef metric, List<Metrics> rows) =>
    metric.duration == null
        ? DurationPrecision.minute
        : columnPrecision(rows.map(metric.duration!));

/// Best and worst rows of one column, for ranked metrics with at least two
/// different values. Ties are all marked.
class ColumnExtremes {
  final Set<int> best;
  final Set<int> worst;
  const ColumnExtremes(this.best, this.worst);
  static const none = ColumnExtremes({}, {});
}

ColumnExtremes columnExtremes(MetricDef metric, List<Metrics> rows) {
  if (!metric.ranked || rows.length < 2) return ColumnExtremes.none;
  final values = rows.map(metric.value).toList();
  final lo = values.reduce((a, b) => a < b ? a : b);
  final hi = values.reduce((a, b) => a > b ? a : b);
  if (lo == hi) return ColumnExtremes.none;
  return ColumnExtremes(
    {for (int i = 0; i < values.length; i++) if (values[i] == lo) i},
    {for (int i = 0; i < values.length; i++) if (values[i] == hi) i},
  );
}

/// Rank of every row in one column, 1 = best, ties share the rank
/// ("competition ranking": 1, 1, 3).
List<int> columnRanks(MetricDef metric, List<Metrics> rows) {
  final values = rows.map(metric.value).toList();
  return [
    for (final v in values) 1 + values.where((other) => other < v).length,
  ];
}

/// Mean rank of every row over [metricIds] (ranked metrics only). Lower is
/// better. Empty selection gives 0 for everyone.
List<double> averageRanks(List<String> metricIds, List<Metrics> rows) {
  final defs = [
    for (final id in metricIds)
      if (metricById(id).ranked) metricById(id),
  ];
  if (defs.isEmpty) return List.filled(rows.length, 0);
  final ranks = [for (final d in defs) columnRanks(d, rows)];
  return [
    for (int i = 0; i < rows.length; i++)
      ranks.map((r) => r[i]).reduce((a, b) => a + b) / defs.length,
  ];
}
