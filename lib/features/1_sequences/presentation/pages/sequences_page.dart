// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/1_sequences/domain/entities/process_entity.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/sequences_bloc.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/sequences_event.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/sequences_state.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/high_order_widgets/orders_list.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/high_order_widgets/machines_list.dart';
import 'package:production_planning/features/1_sequences/presentation/widgets/high_order_widgets/add_order.dart';


class SequencesPage extends StatelessWidget {

  List<Map<String, dynamic>> orders = [
    {
      'name': 'Job A',
      'process': ProcessEntity(
        machines: [
          MachineTypeEntity(
              id: 1, name: 'Machine 1', description: 'Description 1'),
          MachineTypeEntity(
              id: 2, name: 'Machine 2', description: 'Description 2'),
          MachineTypeEntity(
              id: 3, name: 'Machine 3', description: 'Description 3'),
        ],
        durations: [
          const Duration(hours: 2),
          const Duration(hours: 3),
          const Duration(hours: 1)
        ],
      ),
    },
    {
      'name': 'Job B',
      'process': ProcessEntity(
        machines: [
          MachineTypeEntity(
              id: 1, name: 'Machine 4', description: 'Description 1'),
          MachineTypeEntity(
              id: 2, name: 'Machine 5', description: 'Description 2'),
          MachineTypeEntity(
              id: 3, name: 'Machine 6', description: 'Description 3'),
          MachineTypeEntity(
              id: 1, name: 'Machine 1', description: 'Description 1'),
          MachineTypeEntity(
              id: 2, name: 'Machine 2', description: 'Description 2'),
          MachineTypeEntity(
              id: 3, name: 'Machine 3', description: 'Description 3'),
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
  List<MachineTypeEntity> selectedMachines = [];

  String? newOrderName;

  @override
  Widget build(BuildContext context) {
    Color onSecondaryContainer =
        Theme.of(context).colorScheme.onSecondaryContainer;
    Color primaryColor = Theme.of(context).colorScheme.primaryContainer;

    return Scaffold(
      appBar: getAppBar(),
      body: BlocBuilder<SequencesBloc, SequencesState>(
        builder: (context, state) {
          Widget machinesContent = const Center(child: CircularProgressIndicator());

          //HANDLERS BASED ON CURRENT STATE, HERE WE SPECIFY ALL THAT IS DYNAMIC DEPENDING ON STATE
          if(state is SequencesInitialState) BlocProvider.of<SequencesBloc>(context).add(OnSequencesMachineRetrieve());
          if(state is SequencesMachineFailure)machinesContent = const Center(child: Text("Error fetching"));
          if(state is SequencesMachinesSuccess){  
            machinesContent = MachinesList(
                                  machineTypes: state.machines,
                                  onSelectMachine: (machine) => BlocProvider.of<SequencesBloc>(context).add(OnSelectMachine(machine)),
            );
          }
          final machinesList = Container(
            padding: const EdgeInsets.all(16.0),
            child: machinesContent,
          );

          final Widget board;
          if(state.isNewOrder){
            print("order form");
            board = AddOrderForm(selectedMachines: selectedMachines, onSave: _onSaveOrder);
          }else{
            print("order list");
            board = OrderList(orders: orders);
          }

          return Row(
            children: [
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Expanded(
                        flex: 2,
                        child:Container(
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
                            TextButton.icon(
                              onPressed: ()  => BlocProvider.of<SequencesBloc>(context).add(OnUseModeEvent(true)),
                              label: Text(
                                "Agregar trabajo",
                                style: TextStyle(color: primaryColor, fontSize: 18),
                              ),
                              icon: Icon(
                                Icons.upload,
                                color: onSecondaryContainer,
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                minimumSize: const Size(200, 60),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 30, vertical: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Boton ver trabajos
                            TextButton.icon(
                              onPressed: () => BlocProvider.of<SequencesBloc>(context).add(OnUseModeEvent(false)),
                              label: Text(
                                "Ver trabajos",
                                style: TextStyle(color: primaryColor, fontSize: 18),
                              ),
                              icon: Icon(
                                Icons.upload,
                                color: onSecondaryContainer,
                              ),
                              style: TextButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                minimumSize: const Size(200, 60),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 46, vertical: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: board
              ),
            ],
          );
        }
      ),
    );
  }

  void _onSaveOrder(String name, List<MachineTypeEntity> selectedMachines) {

    //LOGGING PURPOSES
    print('Máquinas seleccionadas al guardar: ${selectedMachines.map((m) => m.toString()).toList()}');
    //LOGGING PURPOSES

  /*
    setState(() {
      final process = ProcessEntity(
        machines: selectedMachines,
        durations:
            List.filled(selectedMachines.length, const Duration(hours: 1)),
      );

      orders.add({
        'name': name,
        'process': process,
      });

      _isAddingOrder = false;
      selectedMachines.clear();
    });*/


    //LOGGING PURPOSES
    print('Órdenes después de agregar: ${orders.map((o) => {
          'name': o['name'],
          'process': {
            'machines': o['process'].machines.map((m) => m.toString()).toList(),
            'durations':
                o['process'].durations.map((d) => '${d.inHours}h').toList(),
          },
        }).toList()}');
  }
}
