import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';

class MachinesListView extends StatelessWidget{

  final List<MachineTypeEntity> machineTypes;

  final void Function(int) deleteMachineType;

  MachinesListView({
    super.key, 
    required this.machineTypes,
    required this.deleteMachineType,
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
                  //inside the container we will display in a row the expansion tile and the action buttons
                  child: Row(
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
                              children: [
                                ListTile(
                                  title: Text("ssssss"),
                                )
                              ],
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
                                  onPressed: ()=>deleteMachineType(machineTypes[index].id!), 
                                  icon: const Icon(Icons.delete, color: Colors.red,)
                                ),
                              ],
                            ),
                          ),
                        )
                      ]
                  ),
                );
              },
            );
  }

}