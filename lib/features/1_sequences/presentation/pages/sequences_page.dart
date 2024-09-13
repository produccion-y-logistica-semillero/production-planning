// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/sequences/domain/entities/process_entity.dart';
import 'package:production_planning/features/sequences/presentation/widgets/high_order_widgets/orders_list.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';
import 'package:production_planning/features/sequences/presentation/widgets/high_order_widgets/machines_list.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_state.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_event.dart';
import 'package:production_planning/features/sequences/presentation/widgets/high_order_widgets/add_order.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';

class SequencesPage extends StatefulWidget {
  const SequencesPage({super.key});

  @override
  State<SequencesPage> createState() => _SequencesPageState();
}

class _SequencesPageState extends State<SequencesPage> {
  bool _isAddingOrder = false;
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
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: BlocBuilder<MachineTypesBloc, MachineTypeState>(
                      builder: (context, state) {
                        Widget widget = switch (state) {
                          (MachineTypeInitial _) => const SizedBox(),
                          (MachineTypesRetrieving _) =>
                            const Center(child: CircularProgressIndicator()),
                          (MachineTypesRetrievingError _) =>
                            const Center(child: Text("Error fetching")),
                          (MachineTypesRetrievingSuccess _) => MachinesList(
                              machineTypes: state.machineTypes!,
                              onSelectMachine: (machine) {
                                setState(() {
                                  selectedMachines.add(machine);
                                  print(
                                      'Máquinas seleccionadas ahora: $selectedMachines');
                                });
                              },
                            ),
                          (MachineTypesAddingSuccess _) => MachinesList(
                              machineTypes: state.machineTypes!,
                              onSelectMachine: (machine) {
                                setState(() {
                                  selectedMachines.add(machine);
                                  print(
                                      'Máquinas seleccionadas ahora: $selectedMachines');
                                });
                              },
                            ),
                          (MachineTypesAddingError _) => MachinesList(
                              machineTypes: state.machineTypes!,
                              onSelectMachine: (machine) {
                                setState(() {
                                  selectedMachines.add(machine);
                                  print(
                                      'Máquinas seleccionadas ahora: $selectedMachines');
                                });
                              },
                            ),
                          (MachineTypeDeletionError _) => MachinesList(
                              machineTypes: state.machineTypes!,
                              onSelectMachine: (machine) {
                                setState(() {
                                  selectedMachines.add(machine);
                                  print(
                                      'Máquinas seleccionadas ahora: $selectedMachines');
                                });
                              },
                            ),
                          (MachineTypeDeletionSuccess _) => MachinesList(
                              machineTypes: state.machineTypes!,
                              onSelectMachine: (machine) {
                                setState(() {
                                  selectedMachines.add(machine);
                                  print(
                                      'Máquinas seleccionadas ahora: $selectedMachines');
                                });
                              },
                            ),
                        };

                        if (state is MachineTypeInitial) {
                          BlocProvider.of<MachineTypesBloc>(context)
                              .add(OnMachineTypeRetrieving());
                        }

                        return Container(
                          padding: const EdgeInsets.all(16.0),
                          child: widget,
                        );
                      },
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Boton crear trabajo
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _isAddingOrder = true;
                            });
                          },
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
                          onPressed: () {
                            setState(() {
                              _isAddingOrder = false;
                            });
                          },
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
            child: _isAddingOrder
                ? AddOrderForm(
                    selectedMachines: selectedMachines, onSave: _onSaveOrder)
                : OrderList(orders: orders),
          ),
        ],
      ),
    );
  }

  void _onSaveOrder(String name, List<MachineTypeEntity> selectedMachines) {
    print(
        'Máquinas seleccionadas al guardar: ${selectedMachines.map((m) => m.toString()).toList()}');

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
    });

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
