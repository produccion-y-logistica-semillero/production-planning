import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_event.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_bloc.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machines_event.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machines_state.dart';

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
                                      if(state is MachinesRetrievingSuccess) BlocProvider.of<MachineBloc>(context).add(OnMachinesExpansionCollpased());
                                      else{
                                        BlocProvider.of<MachineBloc>(context).add(OnMachinesRetrieving(machineTypes[index].id!));
                                      }
                                    },
                                    children: 
                                      //here's where we check the state in order to know what to havedisplayed
                                      switch(state){
                                        (MachinesRetrieving _ )=> [const ListTile(title: Text("Loading"),)],
                                        (MachinesRetrievingError _ )=> [const ListTile(title: Text("Error loading"),)],
                                        (MachinesRetrievingSuccess _) => state.machines.map((machine)=>ListTile(
                                              title: Text(machine.id.toString()),
                                            )).toList(),
                                        MachinesStateInitial()=>[ListTile(title: Text("No machines"),)],
                                      }
                                  ),
                                ),
                              ), 
                              //the action buttons inside a container whcih has them in a row
                              Expanded(
                                flex: 1,
                                child: Container(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      IconButton(
                                        onPressed: (){}, 
                                        icon: const Icon(Icons.add)
                                      ),
                                      IconButton(
                                        onPressed: ()=>_deleteMachineType(context, machineTypes[index].id!, index), 
                                        icon: const Icon(Icons.delete, color: Colors.red,)
                                      ),
                                    ],
                                  ),
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

}