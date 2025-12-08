import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/presentation/0_machines/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/presentation/0_machines/bloc/machines_bloc/machine_bloc.dart';
import 'package:production_planning/presentation/0_machines/bloc/machines_bloc/machines_state.dart';
import 'package:production_planning/presentation/0_machines/widgets/low_order_widgets/add_machine_dialog.dart';
import 'package:production_planning/presentation/0_machines/widgets/low_order_widgets/machine_display_tile.dart';
import 'package:production_planning/shared/functions/functions.dart';

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
                } else if (state is MachinesRetrievingSuccess ||
                    state is MachineDeletionSuccess ||
                    state is MachineDeletionError) {
                  children = state.machines!
                      .map(
                        (machine) => MachineDisplayTile(
                          machine,
                          () => _deleteMachine(
                              context, machine.id!, machineType.id!),
                        ),
                      )
                      .toList();
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
                          collapsedBackgroundColor:
                              colorScheme.surfaceContainerLow,
                          backgroundColor: colorScheme.surfaceContainerHigh,
                          onExpansionChanged: (value) {
                            // Used setState with expandedTypes to handle UI expansion and trigger BLoC actions
                            setState(() {
                              if (value) {
                                expandedTypes.add(machineType.id!);
                                BlocProvider.of<MachineBloc>(context)
                                    .retrieveMachines(machineType.id!);
                              } else {
                                expandedTypes.remove(machineType.id!);
                                BlocProvider.of<MachineBloc>(context)
                                    .machinesExpansionCollapses();
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

  void _deleteMachineType(
      BuildContext context, int machineId, int index) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.dangerous, color: Colors.red),
          title: const Text("¿Estas seguro?"),
          content: const Text(
              "Si eliminas este tipo de maquina, todas las maquinas asociadas seran eliminadas, ¿deseas continuar?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("Cancelar"),
            ),
            TextButton(
              onPressed: () {
                BlocProvider.of<MachineTypesBloc>(context)
                    .deleteMachineType(machineId, index);
                Navigator.of(dialogContext).pop();
              },
              child: const Text("Eliminar"),
            ),
          ],
        );
      },
    );
  }

  void _deleteMachine(
      BuildContext context, int machineId, int machineTypeId) async {
    // Show confirmation dialog before deleting
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.dangerous, color: Colors.red),
          title: const Text("Are you sure you want to delete this machine?"),
          actions: [
            // Cancel button (closes the dialog)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("Cancel"),
            ),
            // Confirm button – deletes the machine and refreshes the list
            TextButton(
              onPressed: () async {
                // Delete the machine
                BlocProvider.of<MachineBloc>(context).deleteMachine(machineId);

                // Close the confirmation dialog
                Navigator.of(dialogContext).pop();

                // Wait a short moment to ensure deletion completes before refreshing
                await Future.delayed(const Duration(milliseconds: 200));

                // If the machine type is currently expanded, refresh its machine list
                if (expandedTypes.contains(machineTypeId)) {
                  BlocProvider.of<MachineBloc>(context)
                      .retrieveMachines(machineTypeId);
                }
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );
  }

  void _addNewMachine(
      BuildContext context, int machineId, String machineTypeName) async {
    // Create field controllers
    final TextEditingController controllerCapacity = TextEditingController();
    final TextEditingController controllerPreparation = TextEditingController();
    final TextEditingController controllerRestTime = TextEditingController();
    final TextEditingController controllerContinue = TextEditingController();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController availabilityDateTimeController =
        TextEditingController();
    final TextEditingController quantityController =
        TextEditingController(text: "1"); // default 1

    double? parsePercentage(String text) {
      final normalized = text.replaceAll(',', '.').trim();
      if (normalized.isEmpty) {
        return null;
      }
      return double.tryParse(normalized);
    }

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
          quantityController: quantityController,
          addMachineHandle: () async {
            final quantity = int.tryParse(quantityController.text.trim()) ?? 0;
            final processingPercent = parsePercentage(controllerCapacity.text);
            final preparationPercent =
                parsePercentage(controllerPreparation.text);
            final restPercent = parsePercentage(controllerRestTime.text);
            final continueCapacity =
                int.tryParse(controllerContinue.text.trim());

            final hasInvalidFields = processingPercent == null ||
                processingPercent <= 0 ||
                preparationPercent == null ||
                preparationPercent < 0 ||
                restPercent == null ||
                restPercent < 0 ||
                nameController.text.trim().isEmpty ||
                continueCapacity == null ||
                continueCapacity <= 0 ||
                availabilityDateTimeController.text.trim().isEmpty ||
                quantity <= 0;

            if (hasInvalidFields) {
              // If they are not complete, display a warning dialog box
              await showDialog(
                context: dialogContext,
                builder: (subDialogContext) {
                  return const AlertDialog(
                    icon: Icon(Icons.dangerous_outlined, color: Colors.red),
                    content: Text(
                        "Asegúrese de llenar todos los campos correctamente"),
                  );
                },
              );
              return;
            }

            // getStandardTimesForType is no longer needed since we pass percentages directly

            //Get existing machines from the current state
            final state = context.read<MachineBloc>().state;
            final existingMachines =
                state is MachinesRetrievingSuccess ? state.machines ?? [] : [];
            final existingNames = existingMachines.map((m) => m.name).toList();

            // Determine the starting index for auto-generated names
            final baseName = nameController.text.trim();
            final regex = RegExp('^${RegExp.escape(baseName)}(?: (\\d+))?\$');
            int maxIndex = 0;

            // Find the highest existing suffix number for machines with the same base name
            for (final name in existingNames) {
              final match = regex.firstMatch(name);
              if (match != null) {
                final group = match.group(1);
                final index = group != null ? int.tryParse(group) ?? 1 : 1;
                if (index > maxIndex) maxIndex = index;
              }
            }

            // Add new machines with auto-generated names
            for (int i = 1; i <= quantity; i++) {
              final suffix = (maxIndex + i) == 1 ? '' : ' ${maxIndex + i}';
              final newName = '$baseName$suffix';

              BlocProvider.of<MachineBloc>(context).addNewMachine(
                processingPercent,
                preparationPercent,
                continueCapacity,
                restPercent,
                newName,
                machineId,
                availabilityDateTimeController.text,
              );
            }

            // Close the dialog after adding machines
            Navigator.of(dialogContext).pop();

            // Wait and refresh list
            await Future.delayed(const Duration(milliseconds: 300));
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
