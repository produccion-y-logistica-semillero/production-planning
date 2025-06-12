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

  const OrderMetrics({super.key, required this.orderId});

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

    // También asignar orderId en GanttBloc para cargar environment y reglas
    _ganttBloc.assignOrderId(widget.orderId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Métricas de planificación')),
      body: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _metricsBloc),
          BlocProvider.value(value: _ganttBloc),
        ],
        child: BlocBuilder<MetricsBloc, MetricsState>(
          builder: (context, state) {
            if (state is MetricsLoadingState) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is MetricsErrorState) {
              return Center(child: Text(state.message));
            } else if (state is MetricsLoadedState) {
              final metricsList = state.metrics;

              return BlocBuilder<GanttBloc, GanttState>(
                builder: (context, ganttState) {
                  final env = ganttState.enviroment;
                  final ruleNames = env != null
                      ? env.rules.map((r) => r.value2).toList()
                      : List.generate(metricsList.length, (index) => 'Algoritmo ${index + 1}');

                  return SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (env != null)
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'Ambiente: ${env.name}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Algoritmo')),
                              DataColumn(label: Text('Tiempo muerto')),
                              DataColumn(label: Text('Trabajos')),
                              DataColumn(label: Text('Tardanza máx')),
                              DataColumn(label: Text('Flujo prom')),
                              DataColumn(label: Text('Tardanza prom')),
                              DataColumn(label: Text('Retardo prom')),
                              DataColumn(label: Text('Retrasados')),
                              DataColumn(label: Text('Gantt')),
                            ],
                            rows: List<DataRow>.generate(
                              metricsList.length,
                              (index) {
                                final m = metricsList[index];
                                return DataRow(
                                  cells: [
                                    DataCell(Text(ruleNames[index])),
                                    DataCell(Text('${m.idle}')),
                                    DataCell(Text('${m.totalJobs}')),
                                    DataCell(Text('${m.maxDelay.inMinutes} min')),
                                    DataCell(Text('${m.avarageProcessingTime.inMinutes} min')),
                                    DataCell(Text('${m.avarageDelayTime.inMinutes} min')),
                                    DataCell(Text('${m.avarageLatenessTime.inMinutes} min')),
                                    DataCell(Text('${m.delayedJobs} (${m.percentageDelayedJobs.toStringAsFixed(1)}%)')),
                                    DataCell(
                                      IconButton(
                                        icon: const Icon(Icons.bar_chart),
                                        tooltip: 'Ver Gantt',
                                        onPressed: () {
                                          _ganttBloc.assignOrderAndSelectRuleByIndex(widget.orderId, index);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => BlocProvider.value(
                                                value: _ganttBloc,
                                                child: GanttPage(orderId: widget.orderId, number: 1),
                                              ),
                                            ),
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
                      ],
                    ),
                  );
                },
              );
            } else {
              return const Center(child: Text('Esperando datos...'));
            }
          },
        ),
      ),

    );
  }
}
