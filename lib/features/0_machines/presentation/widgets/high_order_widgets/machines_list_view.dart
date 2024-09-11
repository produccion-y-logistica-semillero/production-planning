import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machine_types_bloc/machine_types_event.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machines_bloc/machine_bloc.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machines_bloc/machines_event.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machines_bloc/machines_state.dart';
import 'package:production_planning/features/0_machines/presentation/widgets/low_order_widgets/add_machine_dialog.dart';
import 'package:production_planning/features/0_machines/presentation/widgets/low_order_widgets/machine_display_tile.dart';

class MachinesListView extends StatelessWidget{

  final List<MachineTypeEntity> machineTypes;

  const MachinesListView({
    super.key, 
    required this.machineTypes,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
              itemCount: machineTypes.length,
              itemBuilder: (context, index) {
                //we wrap it in a container so add margin between but also to add shadow, THIS ONLY AFFECTS THE SHADOW, NOT THE EXPANSION TILE
                //SHAPE ITSELF
                return Container(
                  margin: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        spreadRadius: 3,
                        offset: const Offset(0, 2)
                      )
                    ]
                  ),
                  //so it listens to changes on the machine stae, which means, only this expasion tile will be re rendered
                  child: BlocProvider(
                    create: (context)=>GetIt.instance.get<MachineBloc>(),
                    child: BlocBuilder<MachineBloc,MachinesState> (
                      builder: (context, state) {
                        //inside the container we will display in a row the expansion tile and the action buttons
                        return Row(
                          children: 
                            [
                              //the expansion tile
                              Expanded(
                                flex: 8,
                                //the ClipRReact gives it the round shape to the expansion tile, so is not only the exterior container
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: ExpansionTile(
                                    title: Text(machineTypes[index].name),
                                    subtitle: Text(machineTypes[index].description),
                                    leading: const Icon(Icons.settings_applications_sharp),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                    onExpansionChanged: (value){
                                      //when expanded, if it was expanded, we will collapse and remove the items from state, if it was collapse
                                      //we will trigger the machines retrieving event of that machine type
                                      if(state is MachinesRetrievingSuccess) {
                                        BlocProvider.of<MachineBloc>(context).add(OnMachinesExpansionCollpased());
                                      } else {
                                        BlocProvider.of<MachineBloc>(context).add(OnMachinesRetrieving(machineTypes[index].id!));
                                      }
                                    },
                                    children: 
                                      //here's where we check the state in order to know what to havedisplayed
                                      switch(state){
                                        (MachinesRetrieving _ )=> [const ListTile(title: Text("Loading"),)],
                                        (MachinesRetrievingError _ )=> [const ListTile(title: Text("Error loading"),)],
                                        //here we pass the machines to display
                                        (MachinesRetrievingSuccess _) => state.machines!.map(
                                          (machine)=> MachineDisplayTile(
                                            machine,
                                            ()=>_deleteMachine(context, machine.id!)
                                        )).toList(),
                                        (MachineDeletionSuccess _) => state.machines!.map(
                                          (machine)=> MachineDisplayTile(
                                            machine,
                                            ()=>_deleteMachine(context, machine.id!)
                                        )).toList(),
                                        (MachineDeletionError _)=> state.machines!.map(
                                          (machine)=> MachineDisplayTile(
                                            machine,
                                            ()=>_deleteMachine(context, machine.id!)
                                        )).toList(),
                                        MachinesStateInitial()=>[const ListTile(title: Text(""),)],
                                      }
                                  ),
                                ),
                              ), 
                              //the action buttons inside a container whcih has them in a row
                              Expanded(
                                flex: 1,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      onPressed: ()=>_addNewMachine(context, machineTypes[index].id!, machineTypes[index].name), 
                                      icon: const Icon(Icons.add)
                                    ),
                                    IconButton(
                                      onPressed: ()=>_deleteMachineType(context, machineTypes[index].id!, index), 
                                      icon: const Icon(Icons.delete, color: Colors.red,)
                                    ),
                                  ],
                                ),
                              )
                            ]
                        );
                      }
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
                BlocProvider.of<MachineTypesBloc>(context).add(OnDeleteMachineType(machineId, index));
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
                BlocProvider.of<MachineBloc>(context).add(OnDeleteMachine(machineId));
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

    await showDialog(
      context: context, 
      builder: (dialogContext){
        return AddMachineDialog(
          machineTypeName,
          capacityController: controllerCapacity,
          preparationController: controllerPreparation,
          restTimeController: controllerRestTime,
          continueController: controllerContinue,
          addMachineHandle: ()async{
            if(
              controllerCapacity.text.length != 5 || 
              controllerPreparation.text.length != 5 || 
              controllerRestTime.text.length != 5 || 
              controllerContinue.text.isEmpty
            ){
              //if not all the fields have been added then we show another dialog showing the message
              //we could try to have a custom field in the same dialog that shows the message, but that would imply
              //to handle state in the dialog, and I don't want to deal with that
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
              BlocProvider.of<MachineBloc>(context).add(OnNewMachine(controllerCapacity.text, controllerPreparation.text,  controllerRestTime.text, controllerContinue.text));
              Navigator.of(dialogContext).pop();
            }
          },
        );
      }
    );
  }

}