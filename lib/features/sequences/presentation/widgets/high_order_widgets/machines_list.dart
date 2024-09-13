// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';

class MachinesList extends StatelessWidget {
  final List<MachineTypeEntity> machineTypes;
  final Function(MachineTypeEntity)
      onSelectMachine; // Callback para manejar la selección

  const MachinesList({
    super.key,
    required this.machineTypes,
    required this.onSelectMachine, // Recibir la función de callback
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: machineTypes.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            onSelectMachine(machineTypes[index]); // Llamar al callback
          },
          child: Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.7),
                  offset: const Offset(0, 2),
                  blurRadius: 6,
                )
              ],
            ),
            child: Center(
              child: Text(
                machineTypes[index].name,
                style: TextStyle(color: Colors.black, fontSize: 15),
              ),
            ),
          ),
        );
      },
    );
  }
}
