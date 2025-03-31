import 'package:dartz/dartz.dart' as dartz;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_state.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/gantt_chart.dart';

class GanttPage extends StatelessWidget {
  final int orderId;
  final int number;

  const GanttPage({
    super.key,
    required this.orderId,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: BlocBuilder<GanttBloc, GanttState>(
          builder: (context, state) {
            if (state is GanttOrderRetrieveError) {
              return const Text("Hubo un error encontrando la orden");
            }

            if (state.orderId == null) {
              BlocProvider.of<GanttBloc>(context).assignOrderId(orderId);
              return const Center(child: CircularProgressIndicator());
            }

            final List<Widget> content = [];
            if (state.enviroment != null && state is! GanttPlanningSuccess) {
              content.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    state.enviroment!.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
              content.add(
                Padding(
                  padding: const EdgeInsets.all(80),
                  child: DropdownButtonFormField<int>(
                    value: state.selectedRule,
                    hint: Text(
                      'Selecciona una opción',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    iconSize: 24,
                    elevation: 4,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (int? id) {
                      if (id != null) {
                        BlocProvider.of<GanttBloc>(context).selectRule(id);
                      }
                    },
                    items: state.enviroment!.rules.map((value) {
                      return DropdownMenuItem<int>(
                        value: value.value1,
                        child: Text(
                          value.value2,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            }
            if (state is GanttPlanningLoading) {
              content.add(const Center(child: CircularProgressIndicator()));
            }
            if (state is GanttPlanningError) {
              content.add(const Center(
                  child: Text("Hubo problemas planificando la orden")));
            }
            if (state is GanttPlanningSuccess) {
              content.add(
                GanttChart(
                  number: number,
                  machines: state.planningMachines,
                  selectedRule: state.selectedRule,
                  metrics: state.metrics,
                  schedule: dartz.Tuple2(START_SCHEDULE, END_SCHEDULE),
                  items: state.enviroment!.rules.map((value) {
                    return DropdownMenuItem<int>(
                      value: value.value1,
                      child: Text(value.value2),
                    );
                  }).toList(),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: content,
            );
          },
        ),
      ),
    );
  }
}
