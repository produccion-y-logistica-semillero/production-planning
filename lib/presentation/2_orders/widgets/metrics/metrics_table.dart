import 'package:flutter/material.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/presentation/2_orders/widgets/metrics/metric_definitions.dart';
import 'package:production_planning/presentation/2_orders/widgets/metrics/viz_palette.dart';
import 'package:production_planning/shared/dispatch_rule_info.dart';
import 'package:production_planning/shared/duration_format.dart';

/// Metrics of every algorithm in a table that fits the width of the window
/// (a 14" laptop included): compact times, best value of each column in
/// green with a star, worst in red with a warning sign.
class MetricsTable extends StatefulWidget {
  final List<String> ruleNames;
  final List<Metrics> metrics;
  final void Function(int row) onGantt;
  final void Function(int row) onDetail;

  /// Below this width the table scrolls sideways instead of squeezing.
  static const double minWidth = 880;

  const MetricsTable({
    super.key,
    required this.ruleNames,
    required this.metrics,
    required this.onGantt,
    required this.onDetail,
  });

  @override
  State<MetricsTable> createState() => _MetricsTableState();
}

class _MetricsTableState extends State<MetricsTable> {
  int? _selectedRow;
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = VizPalette.of(context);
    final rows = widget.metrics;
    final precisions = {for (final m in kMetrics) m.id: precisionFor(m, rows)};
    final extremes = {for (final m in kMetrics) m.id: columnExtremes(m, rows)};

    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.primary,
    );

    TableRow header() => TableRow(
          decoration:
              BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
          children: [
            _cell(Text('Algoritmo', style: headerStyle)),
            for (final m in kMetrics)
              Tooltip(
                message: '${m.name}\n${m.description}'
                    '${m.ranked ? '\nMenor es mejor.' : ''}',
                child: _cell(
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(m.header,
                            textAlign: TextAlign.right, style: headerStyle),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.info_outline,
                          size: 12, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            _cell(Text('Ver', style: headerStyle, textAlign: TextAlign.center)),
          ],
        );

    TableRow row(int i) {
      final selected = _selectedRow == i;
      final name = widget.ruleNames[i];
      final info = dispatchRuleInfo(name);
      return TableRow(
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
              : (i.isEven
                  ? Colors.transparent
                  : theme.colorScheme.surfaceContainerLow),
          border: Border(top: BorderSide(color: palette.gridline)),
        ),
        children: [
          _tap(
            i,
            Tooltip(
              message:
                  info == null ? name : '${info.title}\n${info.summary}',
              child: _cell(Text(
                name,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              )),
            ),
          ),
          for (final m in kMetrics)
            _tap(i, _valueCell(context, m, i, precisions[m.id]!,
                extremes[m.id]!, palette)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Ver diagrama de Gantt',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.bar_chart, size: 20),
                onPressed: () => widget.onGantt(i),
              ),
              IconButton(
                tooltip: 'Ver detalle de tareas',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.table_chart_outlined, size: 20),
                onPressed: () => widget.onDetail(i),
              ),
            ],
          ),
        ],
      );
    }

    final table = Table(
      columnWidths: {
        0: const FlexColumnWidth(1.5),
        for (int c = 1; c <= kMetrics.length; c++)
          c: const FlexColumnWidth(1),
        kMetrics.length + 1: const FixedColumnWidth(96),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        header(),
        for (int i = 0; i < rows.length; i++) row(i),
      ],
    );

    final framed = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: table),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Legend(palette: palette),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= MetricsTable.minWidth) return framed;
          return Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: MetricsTable.minWidth, child: framed),
            ),
          );
        }),
      ],
    );
  }

  Widget _tap(int row, Widget child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            setState(() => _selectedRow = _selectedRow == row ? null : row),
        child: child,
      );

  Widget _valueCell(BuildContext context, MetricDef metric, int row,
      DurationPrecision precision, ColumnExtremes ext, VizPalette palette) {
    final theme = Theme.of(context);
    final m = widget.metrics[row];
    final isBest = ext.best.contains(row);
    final isWorst = ext.worst.contains(row);
    final text = metric.format(m, precision);

    final style = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: isBest ? FontWeight.w700 : FontWeight.w400,
      color: isBest
          ? palette.goodText
          : (isWorst ? palette.criticalText : theme.colorScheme.onSurface),
    );

    return Container(
      color: isBest
          ? palette.goodWash
          : (isWorst ? palette.criticalWash : null),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isBest) ...[
            Icon(Icons.star_rounded, size: 14, color: palette.good,
                semanticLabel: 'Mejor'),
            const SizedBox(width: 2),
          ],
          if (isWorst) ...[
            Icon(Icons.warning_amber_rounded, size: 14,
                color: palette.critical, semanticLabel: 'Peor'),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(text, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }

  Widget _cell(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: child,
      );
}

class _Legend extends StatelessWidget {
  final VizPalette palette;
  const _Legend({required this.palette});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget item(IconData icon, Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: muted)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        item(Icons.star_rounded, palette.good, 'Mejor valor de la columna'),
        item(Icons.warning_amber_rounded, palette.critical,
            'Peor valor de la columna'),
        Text(
          'En todas las métricas menor es mejor, salvo el adelanto (no se '
          'califica). Pasa el ratón por los encabezados para ver qué mide cada '
          'una; haz clic en una fila para resaltarla.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }
}
