import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/presentation/0_machines/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/presentation/0_machines/bloc/machines_bloc/machine_bloc.dart';
import 'package:production_planning/presentation/0_machines/bloc/machines_bloc/machines_state.dart';
import 'package:production_planning/presentation/0_machines/widgets/low_order_widgets/add_machine_dialog.dart';
import 'package:production_planning/presentation/0_machines/widgets/low_order_widgets/machine_display_tile.dart';

// Changed to StatefulWidget to manage list expanded state 
class MachinesListView extends StatefulWidget {
  final List<MachineTypeEntity> machineTypes;
  const MachinesListView({super.key, required this.machineTypes});
  // Creates the mutable state for MachinesListView
  @override
  State<MachinesListView> createState() => _MachinesListViewState();
}

class _MachinesListViewState extends State<MachinesListView> {
  final Set<int> expandedTypes = {};

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      // Accessing machineTypes through widget since it is atate class
      itemCount: widget.machineTypes.length,
      itemBuilder: (context, index) {
       // Get the current machine type from the widget's machineTypes list
      final machineType = widget.machineTypes[index];
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(2, 3),
              ),
            ],
            border: Border.all(
              color: colorScheme.outlineVariant,
              width: 0.75,
            ),
          ),
          child: BlocProvider(
            create: (_) => GetIt.instance.get<MachineBloc>(),
            child: BlocBuilder<MachineBloc, MachinesState>(
              builder: (context, state) {
                List<Widget> children = [];
                if (state is MachinesRetrieving) {
                  children = [const ListTile(title: Text("Loading..."))];
                } else if (state is MachinesRetrievingError) {
                  children = [const ListTile(title: Text("Error loading"))];
                } else if (state is MachinesRetrievingSuccess || state is MachineDeletionSuccess || state is MachineDeletionError) {
                  children = state.machines!.map(
                    (machine) => MachineDisplayTile(
                      machine,
                      () => _deleteMachine(context, machine.id!),
                    ),
                  ).toList();
                } else {
                  children = [const ListTile(title: Text(""))];
                }

                return Row(
                  children: [
                    Expanded(
                      flex: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ExpansionTile(
                          title: Text(
                            machineType.name,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            machineType.description,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          leading: Icon(
                            Icons.settings_applications_sharp,
                            color: colorScheme.primary,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          collapsedBackgroundColor: colorScheme.surfaceContainerLow,
                          backgroundColor: colorScheme.surfaceContainerHigh,
                          onExpansionChanged: (value) {
                            // Used setState with expandedTypes to handle UI expansion and trigger BLoC actions
                            setState(() {
                              if (value) {
                                expandedTypes.add(machineType.id!);
                                BlocProvider.of<MachineBloc>(context).retrieveMachines(machineType.id!);
                              } else {
                                expandedTypes.remove(machineType.id!);
                                BlocProvider.of<MachineBloc>(context).machinesExpansionCollapses();
                              }
                            });
                          },
                          children: children,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            onPressed: () => _addNewMachine(
                              context,
                              machineType.id!,
                              machineType.name,
                            ),
                            icon: Icon(Icons.add, color: colorScheme.primary),
                          ),
                          IconButton(
                            onPressed: () => _deleteMachineType(
                              context,
                              machineType.id!,
                              index,
                            ),
                            icon: Icon(Icons.delete, color: colorScheme.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _deleteMachineType(BuildContext context, int machineId, int index) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.dangerous, color: Colors.red),
          title: const Text("¿Estas seguro?"),
          content: const Text("Si eliminas este tipo de maquina, todas las maquinas asociadas seran eliminadas, ¿deseas continuar?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("Cancelar"),
            ),
            TextButton(
              onPressed: () {
                BlocProvider.of<MachineTypesBloc>(context).deleteMachineType(machineId, index);
                Navigator.of(dialogContext).pop();
              },
              child: const Text("Eliminar"),
            ),
          ],
        );
      },
    );
  }

  void _deleteMachine(BuildContext context, int machineId) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.dangerous, color: Colors.red),
          title: const Text("¿Estas seguro de eliminar la maquina?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("Cancelar"),
            ),
            TextButton(
              onPressed: () {
                BlocProvider.of<MachineBloc>(context).deleteMachine(machineId);
                Navigator.of(dialogContext).pop();
              },
              child: const Text("Confirmar"),
            ),
          ],
        );
      },
    );
  }

  void _addNewMachine(BuildContext context, int machineId, String machineTypeName) async {
    // Create field controllers
    final TextEditingController controllerCapacity = TextEditingController();
    final TextEditingController controllerPreparation = TextEditingController();
    final TextEditingController controllerRestTime = TextEditingController();
    final TextEditingController controllerContinue = TextEditingController();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController availabilityDateTimeController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AddMachineDialog(
          machineTypeName,
          nameController: nameController,
          capacityController: controllerCapacity,
          preparationController: controllerPreparation,
          restTimeController: controllerRestTime,
          continueController: controllerContinue,
          availabilityDateTimeController: availabilityDateTimeController,
          addMachineHandle: () async {
            // check fields
            if (
              controllerCapacity.text.length != 5 ||
              controllerPreparation.text.length != 5 ||
              controllerRestTime.text.length != 5 ||
              nameController.text.isEmpty ||
              controllerContinue.text.isEmpty ||
              availabilityDateTimeController.text.isEmpty
            ) {
              // If they are not complete, display a warning dialog box
              await showDialog(
                context: dialogContext,
                builder: (subDialogContext) {
                  return const AlertDialog(
                    icon: Icon(Icons.dangerous_outlined, color: Colors.red),
                    content: Text("Asegúrese de llenar todos los campos correctamente"),
                  );
                },
              );
              return;
            }

            // If they are complete, add new machine
            BlocProvider.of<MachineBloc>(context).addNewMachine(
              controllerCapacity.text,
              controllerPreparation.text,
              controllerContinue.text,
              controllerRestTime.text,
              nameController.text,
              machineId,
              availabilityDateTimeController.text,
            );

            // close create machine dialog
            Navigator.of(dialogContext).pop();

            //Wait to make sure it has been processed correctly
            await Future.delayed(const Duration(milliseconds: 200));

            if (expandedTypes.contains(machineId)) {
              BlocProvider.of<MachineBloc>(context).retrieveMachines(machineId);
            } else {
              setState(() {
                expandedTypes.add(machineId);
              });
            }
          },
        );
      },
    );
  }


}
