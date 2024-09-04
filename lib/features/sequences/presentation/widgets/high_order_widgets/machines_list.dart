// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';

class MachinesList extends StatelessWidget {
  final List<MachineTypeEntity> machineTypes;

  const MachinesList({
    super.key,
    required this.machineTypes,
  });

  @override
  Widget build(BuildContext context) {
    // Color secondaryContainer = Theme.of(context).colorScheme.secondaryContainer;
    return ListView.builder(
      itemCount: machineTypes.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Máquina seleccionada: ${machineTypes[index].name}')),
            );
          },
          child: Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5.0),
                boxShadow: [
                  BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      spreadRadius: 3,
                      offset: const Offset(0, 2))
                ]),
            child: Center(
                child: Text(
              machineTypes[index].name,
              style: TextStyle(color: Colors.black, fontSize: 15),
            )),
          ),
        );
      },
    );
  }
}
