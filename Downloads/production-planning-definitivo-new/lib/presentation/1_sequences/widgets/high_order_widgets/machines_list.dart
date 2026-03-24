import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_type_entity.dart';

class MachinesList extends StatelessWidget {
  final List<MachineTypeEntity> machineTypes;
  final Function(MachineTypeEntity) onSelectMachine;

  const MachinesList({
    super.key,
    required this.machineTypes,
    required this.onSelectMachine,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      itemCount: machineTypes.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            onSelectMachine(machineTypes[index]);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8.0),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.1),
                  offset: const Offset(0, 3),
                  blurRadius: 6,
                )
              ],
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.4),
              ),
            ),
            child: Center(
              child: Text(
                machineTypes[index].name,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
