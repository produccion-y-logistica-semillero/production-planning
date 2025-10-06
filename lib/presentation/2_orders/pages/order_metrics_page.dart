import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/metrics_bloc/metrics_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/metrics_bloc/metrics_state.dart';
import 'package:production_planning/presentation/2_orders/pages/gantt_page.dart';
import 'package:production_planning/presentation/2_orders/pages/gantt_data_table_page.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_state.dart';
import 'package:production_planning/entities/metrics.dart';

class OrderMetrics extends StatefulWidget {
  final int orderId;
  final List<int>? selectedRuleIndexes;

  const OrderMetrics({
    super.key,
    required this.orderId,
    this.selectedRuleIndexes,
  });

  @override
  State<OrderMetrics> createState() => _OrderMetricsState();
}

class _OrderMetricsState extends State<OrderMetrics> {
  late MetricsBloc _metricsBloc;
  late GanttBloc _ganttBloc;
  List<int> _visibleToOriginalIndex = const [];

  @override
  void initState() {
    super.initState();
    _metricsBloc = GetIt.instance<MetricsBloc>();
    _ganttBloc = GetIt.instance<GanttBloc>();

    // Cargar métricas
    _metricsBloc.getTable(widget.orderId);
    // Cargar environment para obtener nombres de reglas
    _ganttBloc.assignOrderId(widget.orderId);
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Devuelve una cadena para el retardo promedio.
  /// Si la clase Metrics no tiene ese campo, retorna '-'.
  String _fmtAverageDelay(Metrics m) {
    // Ajusta aquí si tu clase Metrics tiene otro nombre para ese valor.
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Métricas de la orden #${widget.orderId}',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: BlocBuilder<MetricsBloc, MetricsState>(
          bloc: _metricsBloc,
          builder: (context, state) {
            if (state is MetricsLoadingState) {
              return Center(
                child: CircularProgressIndicator(
                  color: colorScheme.primary,
                ),
              );
            } else if (state is MetricsErrorState) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.message ??
                          'Ocurrió un error al cargar las métricas',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _metricsBloc.getTable(widget.orderId),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
            } else if (state is MetricsLoadedState) {
              final allMetrics = state.metrics;

              return BlocBuilder<GanttBloc, GanttState>(
                bloc: _ganttBloc,
                builder: (context, ganttState) {
                  final env = ganttState.enviroment;

                  final allRuleNames = env != null
                      ? env.rules
                          .map((r) => r.value2?.toString() ?? 'Sin nombre')
                          .toList()
                      : List.generate(
                          allMetrics.length,
                          (index) => 'Algoritmo ${index + 1}',
                        );

                  // Filtrado de métricas según selección
                  final filteredMetrics = <Metrics>[];
                  final filteredRuleNames = <String>[];
                  final filteredIndexes = <int>[];

                  final selectedIndexes = widget.selectedRuleIndexes;

                  if (selectedIndexes != null && selectedIndexes.isNotEmpty) {
                    for (final index in selectedIndexes) {
                      if (index < 0 || index >= allMetrics.length) continue;

                      filteredIndexes.add(index);
                      filteredMetrics.add(allMetrics[index]);
                      filteredRuleNames.add(
                        index < allRuleNames.length
                            ? allRuleNames[index]
                            : 'Algoritmo ${index + 1}',
                      );
                    }
                  } else {
                    for (var index = 0; index < allMetrics.length; index++) {
                      filteredIndexes.add(index);
                      filteredMetrics.add(allMetrics[index]);
                      filteredRuleNames.add(
                        index < allRuleNames.length
                            ? allRuleNames[index]
                            : 'Algoritmo ${index + 1}',
                      );
                    }
                  }

                  if (filteredMetrics.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.analytics_outlined,
                            size: 64,
                            color:
                                colorScheme.onSurfaceVariant.withOpacity(0.6),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No hay métricas para mostrar',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  _visibleToOriginalIndex = filteredIndexes;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header con información
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.primaryContainer,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Orden #${widget.orderId}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  if (env != null)
                                    Text(
                                      'Ambiente: ${env.name}',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 14,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${filteredMetrics.length} algoritmos',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tabla de métricas
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  colorScheme.surfaceContainerHighest,
                                ),
                                dataRowMinHeight: 56,
                                dataRowMaxHeight: 72,
                                columns: [
                                  DataColumn(
                                    label: Text(
                                      'Algoritmo',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    numeric: true,
                                    label: Text(
                                      'Ociosidad',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    numeric: true,
                                    label: Text(
                                      'Trabajos',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Retardo\nprom',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Retrasados',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Visualización',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                                rows: List<DataRow>.generate(
                                  filteredMetrics.length,
                                  (index) {
                                    final m = filteredMetrics[index];
                                    final isEvenRow = index % 2 == 0;

                                    return DataRow(
                                      color: WidgetStateProperty.all(
                                        isEvenRow
                                            ? colorScheme.surface
                                                .withOpacity(0.5)
                                            : Colors.transparent,
                                      ),
                                      cells: [
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  colorScheme.tertiaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              filteredRuleNames[index],
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                color: colorScheme
                                                    .onTertiaryContainer,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${m.idle}',
                                            style: TextStyle(
                                              color: colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${m.totalJobs}',
                                            style: TextStyle(
                                              color: colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            _fmtAverageDelay(m),
                                            style: TextStyle(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${m.delayedJobs}',
                                                style: TextStyle(
                                                  color: m.delayedJobs > 0
                                                      ? colorScheme.error
                                                      : colorScheme.onSurface,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '(${m.percentageDelayedJobs.toStringAsFixed(1)}%)',
                                                style: TextStyle(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                          Builder(
                                            builder: (context) {
                                              final originalIndex =
                                                  _visibleToOriginalIndex[
                                                      index];

                                              return Wrap(
                                                spacing: 4,
                                                runSpacing: 4,
                                                children: [
                                                  FilledButton.icon(
                                                    onPressed: () =>
                                                        _navigateToGantt(
                                                            originalIndex),
                                                    icon: const Icon(
                                                        Icons.bar_chart,
                                                        size: 16),
                                                    label: const Text('Gantt'),
                                                    style:
                                                        FilledButton.styleFrom(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                      backgroundColor:
                                                          colorScheme.tertiary,
                                                      foregroundColor:
                                                          colorScheme
                                                              .onTertiary,
                                                      textStyle:
                                                          const TextStyle(
                                                              fontSize: 12),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                  ),
                                                  FilledButton.icon(
                                                    onPressed: () =>
                                                        _navigateToGanttData(
                                                            originalIndex),
                                                    icon: const Icon(
                                                        Icons.table_chart,
                                                        size: 16),
                                                    label:
                                                        const Text('Detalle'),
                                                    style:
                                                        FilledButton.styleFrom(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                      backgroundColor:
                                                          colorScheme
                                                              .primaryContainer,
                                                      foregroundColor: colorScheme
                                                          .onPrimaryContainer,
                                                      textStyle:
                                                          const TextStyle(
                                                              fontSize: 12),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],
                  );
                },
              );
            } else {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.hourglass_empty,
                      size: 64,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Cargando...',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }
          },
        ),
      ),
    );
  }

  void _navigateToGantt(int originalIndex) {
    _ganttBloc.assignOrderAndSelectRuleByIndex(
      widget.orderId,
      originalIndex,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BlocProvider.value(
          value: _ganttBloc,
          child: GanttPage(
            orderId: widget.orderId,
            number: 1,
          ),
        ),
      ),
    );
  }

  void _navigateToGanttData(int originalIndex) {
    _ganttBloc.assignOrderAndSelectRuleByIndex(
      widget.orderId,
      originalIndex,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BlocProvider.value(
          value: _ganttBloc,
          child: GanttDataTablePage(
            orderId: widget.orderId,
          ),
        ),
      ),
    );
  }
}
