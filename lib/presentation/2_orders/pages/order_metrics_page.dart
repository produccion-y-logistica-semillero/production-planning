import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/metrics_bloc/metrics_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/metrics_bloc/metrics_state.dart';
import 'package:production_planning/presentation/2_orders/pages/gantt_page_container.dart';
import 'package:production_planning/presentation/2_orders/pages/gantt_page.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_state.dart';

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
  late List<int> visibleToOriginalIndex;

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Métricas de Planificación',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _metricsBloc.getTable(widget.orderId);
              _ganttBloc.assignOrderId(widget.orderId);
            },
            tooltip: 'Actualizar métricas',
          ),
        ],
      ),
      body: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _metricsBloc),
          BlocProvider.value(value: _ganttBloc),
        ],
        child: BlocBuilder<MetricsBloc, MetricsState>(
          builder: (context, state) {
            if (state is MetricsLoadingState) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Calculando métricas...',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                  ],
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
                    const SizedBox(height: 16),
                    Text(
                      'Error al cargar las métricas',
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.message,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
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
                builder: (context, ganttState) {
                  final env = ganttState.enviroment;

                  final allRuleNames = env != null
                      ? env.rules.map((r) => r.value2?.toString() ?? 'Sin nombre').toList()
                      : List.generate(
                    allMetrics.length,
                        (index) => 'Algoritmo ${index + 1}',
                  );

                  // Filtrado de métricas según selección
                  List metricsList;
                  List<String> ruleNames;

                  if (widget.selectedRuleIndexes != null &&
                      widget.selectedRuleIndexes!.isNotEmpty) {
                    // Filtrar solo las métricas seleccionadas
                    visibleToOriginalIndex = List.from(widget.selectedRuleIndexes!);
                    metricsList = [
                      for (final i in widget.selectedRuleIndexes!)
                        if (i >= 0 && i < allMetrics.length) allMetrics[i]
                    ];
                    ruleNames = [
                      for (final i in widget.selectedRuleIndexes!)
                        if (i >= 0 && i < allRuleNames.length) allRuleNames[i]
                    ];
                  } else {
                    // Mostrar todos
                    visibleToOriginalIndex = List<int>.generate(allMetrics.length, (i) => i);
                    metricsList = allMetrics;
                    ruleNames = allRuleNames;
                  }

                  if (metricsList.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.analytics_outlined,
                            size: 64,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.6),
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
                                    'Orden ID: ${widget.orderId}',
                                    style: TextStyle(
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
                                '${metricsList.length} algoritmos',
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
                                  colorScheme.primaryContainer.withOpacity(0.5),
                                ),
                                dataRowMinHeight: 56,
                                dataRowMaxHeight: 72,
                                columnSpacing: 24,
                                horizontalMargin: 16,
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
                                    label: Text(
                                      'Tiempo\nmuerto',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
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
                                      'Tardanza\nmáx',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Flujo\nprom',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Tardanza\nprom',
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
                                      'Gantt',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                                rows: List<DataRow>.generate(
                                  metricsList.length,
                                      (index) {
                                    final m = metricsList[index];
                                    final isEvenRow = index % 2 == 0;

                                    return DataRow(
                                      color: WidgetStateProperty.all(
                                        isEvenRow
                                            ? colorScheme.surface.withOpacity(0.5)
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
                                              color: colorScheme.tertiaryContainer,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              ruleNames[index],
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                color: colorScheme.onTertiaryContainer,
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
                                            '${m.maxDelay.inMinutes} min',
                                            style: TextStyle(
                                              color: m.maxDelay.inMinutes > 0
                                                  ? colorScheme.error
                                                  : colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${m.avarageProcessingTime.inMinutes} min',
                                            style: TextStyle(
                                              color: colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${m.avarageDelayTime.inMinutes} min',
                                            style: TextStyle(
                                              color: m.avarageDelayTime.inMinutes > 0
                                                  ? Colors.orange
                                                  : colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${m.avarageLatenessTime.inMinutes} min',
                                            style: TextStyle(
                                              color: colorScheme.onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                                  color: colorScheme.onSurfaceVariant,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                          FilledButton.icon(
                                            onPressed: () {
                                              final originalIndex = visibleToOriginalIndex[index];
                                              _navigateToGantt(originalIndex);
                                            },
                                            icon: const Icon(Icons.bar_chart, size: 18),
                                            label: const Text('Ver'),
                                            style: FilledButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              backgroundColor: colorScheme.tertiary,
                                              foregroundColor: colorScheme.onTertiary,
                                              textStyle: const TextStyle(fontSize: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
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
                      color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Esperando datos...',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
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
}