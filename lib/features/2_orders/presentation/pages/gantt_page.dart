import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_state.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/gantt_chart.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class GanttPage extends StatelessWidget {
  final int orderId;
  const GanttPage({
    super.key,
    required this.orderId
  });

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: getAppBar(),
      body: BlocBuilder<GanttBloc, GanttState>(
        builder: (context, state) {
          if(state is GanttOrderRetrieveError){
            return Text("Hubo un error encontrando la orden");
          }
          if(state.orderId == null){
            BlocProvider.of<GanttBloc>(context).add(AssignOrderId(orderId));
            return Text("Loading");
          }
          List<Widget> content = [];

          if(state.enviroment != null && !(state is GanttPlanningSuccess)){
            content.add(DropdownButton<int>(
                value: state.selectedRule,
                hint: Text('Selecciona una opción'),
                icon: Icon(Icons.arrow_downward),
                iconSize: 24,
                elevation: 16,
                style: TextStyle(color: Colors.deepPurple),
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
             content.add(Center(child: Text("Planficando orden")));
          }
          if(state is GanttPlanningError){
            content.add(Center(child: Text("Hubo problemas planificando la orden")));
          }
          if(state is GanttPlanningSuccess){
            content.add(GanttChart(machines: state.planningMachines, selectedRule: state.selectedRule, items: state.enviroment!.rules.map((value) => DropdownMenuItem(
                    value: value.value1,
                    child: Text(value.value2),
                  )
                ).toList(),));
          }
          return Column(
            children: content
          );
        },
      ),
    );
  }
}
