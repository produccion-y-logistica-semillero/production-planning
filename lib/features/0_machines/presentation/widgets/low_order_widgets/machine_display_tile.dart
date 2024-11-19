import 'package:flutter/material.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';

class MachineDisplayTile extends StatelessWidget {
  final MachineEntity machine;
  final void Function() deleteHandler;

  const MachineDisplayTile(this.machine, this.deleteHandler, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 300,
            child: Text(
              machine.name,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 200,
            child: Text(
              machine.status ?? 'Unknown',
              style: TextStyle(
                color: colorScheme.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Tiempo de procesamiento ${machine.processingTime.toString().substring(0, 8)}',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: deleteHandler,
            icon: Icon(
              Icons.delete,
              color: colorScheme.error,
            ),
            tooltip: 'Eliminar Máquina',
          ),
        ],
      ),
    );
  }
}
