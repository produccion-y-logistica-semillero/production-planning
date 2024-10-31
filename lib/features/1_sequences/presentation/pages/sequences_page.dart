// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/1_sequences/domain/entities/process_entity.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/new_process_bloc/sequences_event.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/new_process_bloc/sequences_state.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/high_order_widgets/orders_list.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/low_order_widgets/button_mode.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/high_order_widgets/machines_list.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/high_order_widgets/add_order.dart';


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
        if (state is SequencesInitialState) BlocProvider.of<SequencesBloc>(context).add(OnSequencesMachineRetrieve());
        if (state is SequencesMachineFailure) machinesContent = const Center(child: Text("Error fetching"));
        if (state.machines != null) {
          machinesContent = MachinesList(
            machineTypes: state.machines!,
            onSelectMachine: (machine) => BlocProvider.of<SequencesBloc>(context).add(OnSelectMachine(machine)),
          );
        }
        final machinesList = Container(
          padding: const EdgeInsets.all(16.0),
          child: machinesContent,
        );

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

        return Row(
          children: [
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    if (state.isNewOrder)
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.all(16.0),
                          child: machinesList,
                        ),
                      ),
                    Expanded(
                      flex: 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Boton crear trabajo
                          ButtonMode(
                              callback: () => BlocProvider.of<SequencesBloc>(context).add(OnUseModeEvent(true)),
                              labelText: "Agregar trabajo",
                              icon: Icons.upload,
                              horizontalPadding: 30),
                          const SizedBox(height: 20),
                          // Boton ver trabajos
                          ButtonMode(
                              callback: () => BlocProvider.of<SequencesBloc>(context).add(OnUseModeEvent(false)),
                              labelText: "Ver trabajos",
                              icon: Icons.upload,
                              horizontalPadding: 46),
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
    BlocProvider.of<SequencesBloc>(context).add(OnSequencesSaveProcess(name));
  }
}
