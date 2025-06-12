import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/presentation/0_machines/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/presentation/0_machines/bloc/machines_bloc/machine_bloc.dart';
import 'package:production_planning/presentation/0_machines/bloc/machines_bloc/machines_state.dart';
import 'package:production_planning/presentation/0_machines/widgets/low_order_widgets/add_machine_dialog.dart';
import 'package:production_planning/presentation/0_machines/widgets/low_order_widgets/machine_display_tile.dart';

class MachinesListView extends StatelessWidget{

  final List<MachineTypeEntity> machineTypes;

  const MachinesListView({
    super.key, 
    required this.machineTypes,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      itemCount: machineTypes.length,
      itemBuilder: (context, index) {
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
            create: (context) => GetIt.instance.get<MachineBloc>(),
            child: BlocBuilder<MachineBloc, MachinesState>(
              builder: (context, state) {
                List<Widget> children = [];
                if (state is MachinesRetrieving) {
                  children = [const ListTile(title: Text("Loading..."))];
                } else if (state is MachinesRetrievingError) {
                  children = [const ListTile(title: Text("Error loading"))];
                } else if (state is MachinesRetrievingSuccess) {
                  children = state.machines!.map(
                    (machine) => MachineDisplayTile(
                      machine,
                      () => _deleteMachine(context, machine.id!),
                    ),
                  ).toList();
                } else if (state is MachineDeletionSuccess || state is MachineDeletionError) {
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
                            machineTypes[index].name,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            machineTypes[index].description,
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
                            if (state is MachinesRetrievingSuccess) {
                              BlocProvider.of<MachineBloc>(context).machinesExpansionCollapses();
                            } else {
                              BlocProvider.of<MachineBloc>(context).retrieveMachines(machineTypes[index].id!);
                            }
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
                              machineTypes[index].id!,
                              machineTypes[index].name,
                            ),
                            icon: Icon(
                              Icons.add,
                              color: colorScheme.primary,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _deleteMachineType(
                              context,
                              machineTypes[index].id!,
                              index,
                            ),
                            icon: Icon(
                              Icons.delete,
                              color: colorScheme.error,
                            ),
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

  void _deleteMachineType(BuildContext context, int machineId, int index) async{
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.dangerous, color: Colors.red,),
          title: const Text("¿Estas seguro?"),
          content: const Text("Si eliminas este tipo de maquina, todas las maquinas asociadas seran eliminadas, ¿deseas continuar?"),
          actions: [
            TextButton(
              onPressed: ()=>Navigator.of(dialogContext).pop(), 
              child: const Text("Cancelar")
            ),
            TextButton(
              onPressed: (){
                BlocProvider.of<MachineTypesBloc>(context).deleteMachineType(machineId, index);
                Navigator.of(dialogContext).pop();
              }, 
              child: const Text("Eliminar")
            )
          ],
        );
      }
    );
  }

  void _deleteMachine(BuildContext context, int machineId) async{
    await showDialog(
      context: context, 
      builder: (dialogContext){
        return AlertDialog(
          icon:  const Icon(Icons.dangerous, color: Colors.red,),
          title: const Text("¿Estas seguro de eliminar la maquina?"),
          actions: [
            TextButton(
              onPressed: ()=>Navigator.of(dialogContext).pop(), 
              child: const Text("Cancelar"),
            ),
            TextButton(
              onPressed: (){
                BlocProvider.of<MachineBloc>(context).deleteMachine(machineId);
                Navigator.of(dialogContext).pop();
              }, 
              child: const Text("Confirmar")
            ),

          ]
        );
      }
    );
  }

  void _addNewMachine(BuildContext context, int machineId, String machineTypeName) async{
    final TextEditingController controllerCapacity = TextEditingController();
    final TextEditingController controllerPreparation = TextEditingController();
    final TextEditingController controllerRestTime = TextEditingController();
    final TextEditingController controllerContinue = TextEditingController();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController availabilityDateTimeController = TextEditingController(); 
    print("** ______________**");
    await showDialog(
      context: context, 
      builder: (dialogContext){
        return AddMachineDialog(
          machineTypeName,
          nameController: nameController,
          capacityController: controllerCapacity,
          preparationController: controllerPreparation,
          restTimeController: controllerRestTime,
          continueController: controllerContinue,
          availabilityDateTimeController: availabilityDateTimeController,
          addMachineHandle: ()async{
            print("__________**_________Adding new machine with typeId: $machineId");
            if(
              controllerCapacity.text.length != 5 || 
              controllerPreparation.text.length != 5 || 
              controllerRestTime.text.length != 5 || 
              nameController.text.isEmpty ||
              controllerContinue.text.isEmpty ||
              availabilityDateTimeController.text.isEmpty
            ){
              //if not all the fields have been added then we show another dialog showing the message
              //we could try to have a custom field in the same dialog that shows the message, but that would imply
              //to handle state in the dialog, and I don't want to deal with that
              print("___________________Not all fields have been filled");
              await showDialog(
                context: dialogContext,
                builder: (subDialogContext){
                  return const AlertDialog(
                    icon: Icon(Icons.dangerous_outlined, color: Colors.red,),
                    content: Text("Asegurese de llenar todos los campos correctamente"),
                  );
                }
              );
            }
            //else if to check if the inputs are correct, for instance, no 12:85
            else {
              print("___________________Adding new machine with typeId: $machineId");
              BlocProvider.of<MachineBloc>(context).addNewMachine(controllerCapacity.text, controllerPreparation.text,  controllerContinue.text, controllerRestTime.text, nameController.text, machineId, availabilityDateTimeController.text); 
              Navigator.of(dialogContext).pop();
            }
          },
        );
      }
    );
  }

}