import 'package:flutter/material.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/presentation/2_orders/widgets/metrics/metric_definitions.dart';
import 'package:production_planning/presentation/2_orders/widgets/metrics/viz_palette.dart';
import 'package:production_planning/shared/duration_format.dart';

/// Comparison of every algorithm at a glance:
///  1. who wins each objective (cards);
///  2. one metric across algorithms, best to worst (bars);
///  3. every algorithm's position in every metric, and an overall ranking
///     over the objectives the user picks (rank map).
class MetricsDashboard extends StatefulWidget {
  final List<String> ruleNames;
  final List<Metrics> metrics;
  final void Function(int row) onGantt;
  final void Function(int row) onDetail;

  const MetricsDashboard({
    super.key,
    required this.ruleNames,
    required this.metrics,
    required this.onGantt,
    required this.onDetail,
  });

  @override
  State<MetricsDashboard> createState() => _MetricsDashboardState();
}

class _MetricsDashboardState extends State<MetricsDashboard> {
  String _barMetric = 'makespan';
  final Set<String> _scoreMetrics = {...kHeadlineMetricIds};

  List<Metrics> get _rows => widget.metrics;

  String _fmt(MetricDef m, int row) =>
      m.format(_rows[row], precisionFor(m, _rows));

  void _openActions(int row) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(widget.ruleNames[row]),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onGantt(row);
            },
            child: const ListTile(
              leading: Icon(Icons.bar_chart),
              title: Text('Ver diagrama de Gantt'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onDetail(row);
            },
            child: const ListTile(
              leading: Icon(Icons.table_chart_outlined),
              title: Text('Ver detalle de tareas'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _winnerCards(context),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final bars = _panel(context, 'Comparar por métrica', _bars(context));
            final map = _panel(
                context, 'Posiciones y puntaje global', _rankMap(context));
            if (c.maxWidth < 1100) {
              return Column(children: [bars, const SizedBox(height: 16), map]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: bars),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: map),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, String title, Widget child) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ── 1. Winner of each objective ────────────────────────────────────────────

  Widget _winnerCards(BuildContext context) {
    final theme = Theme.of(context);
    final palette = VizPalette.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget card(MetricDef m) {
      final values = _rows.map(m.value).toList();
      final order = List.generate(values.length, (i) => i)
        ..sort((a, b) => values[a].compareTo(values[b]));
      final best = values[order.first];
      final winners = [for (final i in order) if (values[i] == best) i];
      final allTied = winners.length == values.length;
      final runnerUp = order.firstWhere((i) => values[i] != best,
          orElse: () => -1);

      String detail;
      if (allTied) {
        detail = 'Todos los algoritmos empatan';
      } else if (winners.length > 1) {
        detail = 'Empate entre ${winners.length} algoritmos';
      } else if (runnerUp >= 0) {
        final d = m.duration;
        final gap = d == null
            ? '${(values[runnerUp] - best).round()}'
            : formatDuration(d(_rows[runnerUp]) - d(_rows[winners.first]),
                precisionFor(m, _rows));
        detail = '$gap menos que ${widget.ruleNames[runnerUp]}';
      } else {
        detail = '';
      }

      return SizedBox(
        width: 230,
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: allTied ? null : () => _openActions(winners.first),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: m.description,
                    child: Text('Menor ${m.name.toLowerCase()}',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: muted)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.emoji_events_outlined,
                          size: 18,
                          color: allTied ? muted : palette.good),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          allTied
                              ? '—'
                              : winners
                                  .map((i) => widget.ruleNames[i])
                                  .join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_fmt(m, winners.first),
                      style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(detail,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final id in kHeadlineMetricIds) card(metricById(id))],
    );
  }

  // ── 2. One metric across algorithms ────────────────────────────────────────

  Widget _bars(BuildContext context) {
    final theme = Theme.of(context);
    final palette = VizPalette.of(context);
    final metric = metricById(_barMetric);
    final values = _rows.map(metric.value).toList();
    final order = List.generate(values.length, (i) => i)
      ..sort((a, b) {
        final c = values[a].compareTo(values[b]);
        return c != 0 ? c : a.compareTo(b);
      });
    final maxValue = values.fold<num>(0, (a, b) => b > a ? b : a);
    final ext = columnExtremes(metric, _rows);
    final ranks = columnRanks(metric, _rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in kMetrics)
              ChoiceChip(
                label: Text(m.name),
                selected: m.id == _barMetric,
                onSelected: (_) => setState(() => _barMetric = m.id),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          metric.ranked
              ? '${metric.description} Ordenado de mejor a peor.'
              : metric.description,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final i in order)
          Tooltip(
            message: '${widget.ruleNames[i]}\n${metric.name}: '
                '${metric.format(_rows[i], DurationPrecision.microsecond)}'
                '${metric.ranked ? '\nPuesto ${ranks[i]} de ${_rows.length}' : ''}'
                '\nClic para ver su Gantt o detalle',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _openActions(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(widget.ruleNames[i],
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: LayoutBuilder(builder: (context, c) {
                        final frac =
                            maxValue <= 0 ? 0.0 : values[i] / maxValue;
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 18,
                              decoration: BoxDecoration(
                                color: palette.track,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Container(
                              height: 18,
                              width: values[i] <= 0
                                  ? 0
                                  : (c.maxWidth * frac).clamp(4.0, c.maxWidth),
                              decoration: BoxDecoration(
                                color: palette.series,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: Row(
                        children: [
                          if (ext.best.contains(i)) ...[
                            Icon(Icons.star_rounded,
                                size: 14, color: palette.good),
                            const SizedBox(width: 2),
                          ],
                          Flexible(
                            child: Text(
                              _fmt(metric, i) +
                                  (ext.best.contains(i) ? '  Mejor' : ''),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                                fontWeight: ext.best.contains(i)
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: ext.best.contains(i)
                                    ? palette.goodText
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── 3. Rank map and overall score ──────────────────────────────────────────

  Widget _rankMap(BuildContext context) {
    final theme = Theme.of(context);
    final palette = VizPalette.of(context);
    final ranked = [for (final m in kMetrics) if (m.ranked) m];
    final ranksBy = {for (final m in ranked) m.id: columnRanks(m, _rows)};
    final avg = averageRanks(_scoreMetrics.toList(), _rows);
    final order = List.generate(_rows.length, (i) => i)
      ..sort((a, b) {
        final c = avg[a].compareTo(avg[b]);
        return c != 0 ? c : a.compareTo(b);
      });
    final n = _rows.length;
    final muted = theme.colorScheme.onSurfaceVariant;

    String short(MetricDef m) => m.header.replaceAll('\n', ' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Puesto de cada algoritmo en cada métrica (1 = mejor). Marca las '
          'métricas que te importan: el orden de las filas y el recomendado '
          'se calculan con el puesto promedio en ellas.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in ranked)
              FilterChip(
                label: Text(m.name),
                selected: _scoreMetrics.contains(m.id),
                onSelected: (on) => setState(() {
                  on ? _scoreMetrics.add(m.id) : _scoreMetrics.remove(m.id);
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            0: const FlexColumnWidth(1.6),
            for (int c = 1; c <= ranked.length; c++)
              c: const FlexColumnWidth(1),
            ranked.length + 1: const FlexColumnWidth(1.1),
          },
          children: [
            TableRow(children: [
              const SizedBox(),
              for (final m in ranked)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Tooltip(
                    message: m.description,
                    child: Text(
                      short(m),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _scoreMetrics.contains(m.id)
                            ? theme.colorScheme.onSurface
                            : muted.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text('Puesto\npromedio',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            for (int pos = 0; pos < order.length; pos++)
              TableRow(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: InkWell(
                    onTap: () => _openActions(order[pos]),
                    child: Row(
                      children: [
                        if (pos == 0 && _scoreMetrics.isNotEmpty) ...[
                          Tooltip(
                            message: 'Recomendado para los objetivos marcados',
                            child: Icon(Icons.emoji_events,
                                size: 16, color: palette.good),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            widget.ruleNames[order[pos]],
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final m in ranked)
                  _rankCell(context, palette, m, order[pos],
                      ranksBy[m.id]![order[pos]], n),
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    _scoreMetrics.isEmpty
                        ? '—'
                        : avg[order[pos]].toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ]),
          ],
        ),
        if (_scoreMetrics.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.emoji_events, size: 18, color: palette.good),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Recomendado para estos objetivos: '),
                  TextSpan(
                      text: widget.ruleNames[order.first],
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ])),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _rankCell(BuildContext context, VizPalette palette, MetricDef m,
      int row, int rank, int n) {
    final included = _scoreMetrics.contains(m.id);
    final color = palette.rankColor(rank, n);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message: '${widget.ruleNames[row]} · ${m.name}\n'
            '${_fmt(m, row)} — puesto $rank de $n',
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: included ? color : color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: included
                  ? palette.rankInk(rank, n)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
