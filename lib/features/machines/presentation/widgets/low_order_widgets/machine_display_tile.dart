import 'package:flutter/material.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';

class MachineDisplayTile extends StatelessWidget{

  final MachineEntity machine;
  final void Function() deleteHandler;

  const MachineDisplayTile(this.machine, this.deleteHandler);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          SizedBox(
            width: 100,
            child: Text(machine.id!.toString())
          ),
          SizedBox(
            width: 100,
            child: Text(machine.status!),
          ),
          SizedBox(
            width: 400,
            child:  Text('Tiempo de procesamiento ${machine.processingTime.toString().substring(0,8)}'),
          ),
          IconButton(
            onPressed: deleteHandler,
            icon: Icon(Icons.delete, color: Colors.red,)
          )
        ],
      ),
    );
  }

}