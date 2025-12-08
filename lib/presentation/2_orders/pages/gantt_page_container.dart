import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/pages/gantt_page.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class GanttPageContainer extends StatefulWidget {
  final int orderId;

  const GanttPageContainer({super.key, required this.orderId});

  @override
  State<GanttPageContainer> createState() => _GanttPageContainerState();
}

class _GanttPageContainerState extends State<GanttPageContainer> {
  int number = 1;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(),
      body: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    IconButton(
                        onPressed: () => printInfo(context,
                            title: 'Programar orden',
                            content:
                                'Aca se muestra el ambiente de manofactura en el que cae la orden seleccionada, con este ambiente puedes seleccionar cualqueira de las reglas mostradas en la lista, cada regla usa algoritmos distintos para realizar la planificacion, puedes agregar mas pantallas para visualizar varios algoritmos al tiempo.'),
                        icon: const Icon(Icons.info))
                  ],
                ),
              ),
              Expanded(
                flex: 15,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () => {
                        setState(() {
                          number++;
                        })
                      },
                      style: const ButtonStyle(
                          backgroundColor:
                              WidgetStatePropertyAll(Colors.green)),
                      child: const Icon(Icons.add),
                    ),
                    ElevatedButton(
                      onPressed: () => {
                        if (number > 1)
                          setState(() {
                            number--;
                          })
                      },
                      style: const ButtonStyle(
                          backgroundColor: WidgetStatePropertyAll(Colors.red)),
                      child: const Icon(Icons.remove),
                    ),
                  ],
                ),
              )
            ],
          ),
          Row(children: [
            for (int i = 0; i < number; i++)
              BlocProvider<GanttBloc>(
                create: (context) => GetIt.instance.get<GanttBloc>(),
                child: Expanded(
                  child: GanttPage(orderId: widget.orderId, number: number),
                ),
              )
          ])
        ],
      ),
    );
  }
}
