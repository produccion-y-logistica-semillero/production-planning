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
import 'package:production_planning/presentation/2_orders/widgets/metrics/metrics_dashboard.dart';
import 'package:production_planning/presentation/2_orders/widgets/metrics/metrics_table.dart';

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

                      state.message,

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

                      ? env.rules.map((r) => r.value2.toString()).toList()
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


                  final totalJobs = filteredMetrics.first.totalJobs;

                  return DefaultTabController(
                    length: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Encabezado: orden, ambiente, trabajos y algoritmos.
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: colorScheme.primaryContainer),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  color: colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(children: [
                                    TextSpan(
                                      text: 'Orden #${widget.orderId}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    if (env != null)
                                      TextSpan(text: '  ·  Ambiente: ${env.name}'),
                                    TextSpan(
                                        text: '  ·  $totalJobs '
                                            '${totalJobs == 1 ? 'trabajo' : 'trabajos'}'),
                                    TextSpan(
                                        text: '  ·  ${filteredMetrics.length} '
                                            '${filteredMetrics.length == 1 ? 'algoritmo' : 'algoritmos'}'),
                                  ]),
                                  style: TextStyle(color: colorScheme.onSurface),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const TabBar(
                          tabAlignment: TabAlignment.start,
                          isScrollable: true,
                          tabs: [
                            Tab(
                                icon: Icon(Icons.table_rows_outlined),
                                text: 'Tabla'),
                            Tab(
                                icon: Icon(Icons.dashboard_outlined),
                                text: 'Dashboard'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: MetricsTable(
                                  ruleNames: filteredRuleNames,
                                  metrics: filteredMetrics,
                                  onGantt: (row) =>
                                      _navigateToGantt(filteredIndexes[row]),
                                  onDetail: (row) => _navigateToGanttData(
                                      filteredIndexes[row]),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: MetricsDashboard(
                                  ruleNames: filteredRuleNames,
                                  metrics: filteredMetrics,
                                  onGantt: (row) =>
                                      _navigateToGantt(filteredIndexes[row]),
                                  onDetail: (row) => _navigateToGanttData(
                                      filteredIndexes[row]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
