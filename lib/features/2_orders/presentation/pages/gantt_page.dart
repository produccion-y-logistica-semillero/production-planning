import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_state.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/gantt_chart.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

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

    return Column(
        children: [
          BlocBuilder<GanttBloc, GanttState>(
            builder: (context, state) {
              if(state is GanttOrderRetrieveError){
                return const Text("Hubo un error encontrando la orden");
              }
              if(state.orderId == null){
                BlocProvider.of<GanttBloc>(context).add(AssignOrderId(orderId));
                return const CircularProgressIndicator();
              }
              List<Widget> content = [];
          
              if(state.enviroment != null && state is! GanttPlanningSuccess){
                content.add(
                  Text(state.enviroment!.name)
                );
                content.add(DropdownButton<int>(
                    value: state.selectedRule,
                    hint: const Text('Selecciona una opción'),
                    icon: const Icon(Icons.arrow_downward),
                    iconSize: 24,
                    elevation: 16,
                    style: const TextStyle(color: Colors.deepPurple),
                    underline: Container(
                      height: 2,
                      color: Colors.deepPurpleAccent,
                    ),
                    onChanged: (int? id) {
                      if(id != null) BlocProvider.of<GanttBloc>(context).add(SelectRule(id));
                    },
                    items: state.enviroment!.rules.map((value) => DropdownMenuItem(
                        value: value.value1,
                        child: Text(value.value2),
                      )
                    ).toList(),
                  )
                );
              }
              if(state is GanttPlanningLoading){
                 content.add(const Center(child: CircularProgressIndicator()));
              }
              if(state is GanttPlanningError){
                content.add(const Center(child: Text("Hubo problemas planificando la orden")));
              }
              if(state is GanttPlanningSuccess){
                content.add(
                  GanttChart(
                    number : number,
                    machines: state.planningMachines, 
                    selectedRule: state.selectedRule,
                    metrics:  state.metrics,
                    items: state.enviroment!.rules.map((value) => DropdownMenuItem(
                        value: value.value1,
                        child: Text(value.value2),
                      )
                    ).toList(),
                  )
                );
              }
              return Center(
                child: Column(
                  children: content
                ),
              );
            },
          ),
        ],
      );
  }
}
