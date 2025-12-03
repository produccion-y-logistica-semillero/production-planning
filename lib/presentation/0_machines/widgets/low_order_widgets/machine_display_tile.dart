import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/presentation/0_machines/bloc/machine_inactivities_cubit/machine_inactivities_cubit.dart';
import 'package:production_planning/presentation/0_machines/widgets/low_order_widgets/machine_inactivities_dialog.dart';

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
            onPressed: () => _openInactivitiesDialog(context),
            icon: Icon(
              Icons.pause_circle_outline,
              color: colorScheme.primary,
            ),
            tooltip: 'Configurar inactividades',
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

  void _openInactivitiesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return BlocProvider(
          create: (_) => GetIt.instance
              .get<MachineInactivitiesCubit>()
            ..initialize(machine),
          child: MachineInactivitiesDialog(machine: machine),
        );
      },
    );
  }
}
