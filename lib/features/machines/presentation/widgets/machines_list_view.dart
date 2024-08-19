import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';

class MachinesListView extends StatelessWidget{

  final List<MachineEntity> machines;

  MachinesListView({super.key, required this.machines});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ListView.builder(
                itemCount: machines.length,
                itemBuilder: (context, index) {
                  return Container(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                              const SizedBox(width: 15,),
                              Text(machines[index].name, style:  TextStyle(fontSize: 25, fontWeight: FontWeight.bold),),
                              const SizedBox(width: 15,),
                              SizedBox(
                                  width: 500,
                                  child: Text(machines[index].description, style:  TextStyle(fontSize: 20),)
                              ),
                          ]
                        ),
                        TextButton(onPressed: (){}, child: Text("Agregar maquina especifica")),
                      ],
                    ),
                  );
                },
              ),
    );
  }

}