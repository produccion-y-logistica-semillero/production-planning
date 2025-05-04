// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/entities/process_entity.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_state.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/orders_list.dart';
import 'package:production_planning/presentation/1_sequences/widgets/low_order_widgets/button_mode.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/machines_list.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/add_order.dart';


class SequencesPage extends StatelessWidget {

  final List<Map<String, dynamic>> orders = [
    {
      'name': 'Job A',
      'process': ProcessEntity(
        machines: [
          MachineTypeEntity(id: 1, name: 'Machine 1', description: 'Description 1'),
          MachineTypeEntity(id: 2, name: 'Machine 2', description: 'Description 2'),
          MachineTypeEntity(id: 3, name: 'Machine 3', description: 'Description 3'),
        ],
        durations: [const Duration(hours: 2), const Duration(hours: 3), const Duration(hours: 1)],
      ),
    },
    {
      'name': 'Job B',
      'process': ProcessEntity(
        machines: [
          MachineTypeEntity(id: 1, name: 'Machine 4', description: 'Description 1'),
          MachineTypeEntity(id: 2, name: 'Machine 5', description: 'Description 2'),
          MachineTypeEntity(id: 3, name: 'Machine 6', description: 'Description 3'),
          MachineTypeEntity(id: 1, name: 'Machine 1', description: 'Description 1'),
          MachineTypeEntity(id: 2, name: 'Machine 2', description: 'Description 2'),
          MachineTypeEntity(id: 3, name: 'Machine 3', description: 'Description 3'),
        ],
        durations: [
          const Duration(hours: 2),
          const Duration(hours: 3),
          const Duration(hours: 1),
          const Duration(hours: 2),
          const Duration(hours: 3),
          const Duration(hours: 1)
        ],
      ),
    },
  ];
  final List<MachineTypeEntity> selectedMachines = [];


  SequencesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: getAppBar(),
      body: BlocBuilder<SequencesBloc, SequencesState>(builder: (context, state) {
        Widget machinesContent = const Center(child: CircularProgressIndicator());

        //HANDLERS BASED ON CURRENT STATE, HERE WE SPECIFY ALL THAT IS DYNAMIC DEPENDING ON STATE
        if (state is SequencesInitialState) BlocProvider.of<SequencesBloc>(context).retrieveSequencesMachine(); 
        if (state is SequencesMachineFailure) machinesContent = const Center(child: Text("Error fetching"));
        if (state.machines != null) {
          machinesContent = MachinesList(
            machineTypes: state.machines!,
            onSelectMachine: (machine) => BlocProvider.of<SequencesBloc>(context).selectMachine(machine),
          );
        }
        final machinesList = machinesContent;

        final Widget board;
        if (state.isNewOrder) {
          board = AddOrderForm(
            selectedMachines: selectedMachines,
            onSave: (name) => _onSaveOrder(context, name),
            state: state,
          );
        } else {
          board = BlocProvider(
            create: (context) => GetIt.instance.get<SeeProcessBloc>(),
            child: const OrderList(),
          );
        }

        return 
            Row(
              children: [
                IconButton(
              onPressed: ()=>printInfo(context, 
                title: 'Secuencias', 
                content: 'Una secuencia se refiere al proceso de fabricacion de un producto, aca se define la secuencia de maquinas por las que se debe pasar para la fabricacion, el orden representa pre requisitos, y en cada paso por una maquina, o "tarea" se especifica cuanto tiempo en promedio se requiere en esa maquina, por ejemplo, la produccion de pan:\n\nTarea 1: Maquina de mezclado, 20min\nTarea 2: Camara de reposo, 10 min\nTarea 3: Maquina divisora, 4 min\nTarea 5: Maquina de formado, 15 min\nTarea 6: Maquina de horneado, 1 hora\nTarea 7: Maquina de enfriado 40 min'
              ), 
              icon: const Icon(Icons.info)),
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        if (state.isNewOrder)
                          Expanded(
                            flex: 2,
                            child: machinesList,
                          ),
                        Expanded(
                          flex: 1,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Boton crear trabajo
                              ButtonMode(
                                  callback: state.isNewOrder ?
                                     () => BlocProvider.of<SequencesBloc>(context).useMode(false): 
                                     () => BlocProvider.of<SequencesBloc>(context).useMode(true),
                                  labelText: state.isNewOrder ? "Ver Secuencias": "Nueva Orden",
                                  icon: Icons.roller_shades_closed_outlined,
                                  horizontalPadding: 30),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(flex: 2, child: board),
              ],
            );
      }),
    );
  }

  void _onSaveOrder(BuildContext context, String name) {
    BlocProvider.of<SequencesBloc>(context).saveProcess(name);
  }
}
