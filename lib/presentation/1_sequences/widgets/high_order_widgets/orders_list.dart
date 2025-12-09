import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_state.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/sequence_editor_panel.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/graph_editor.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/sequence_selector_modal.dart';


class OrderList extends StatelessWidget {
  final TextEditingController nameController;
  final GlobalKey<NodeEditorState> nodeEditorKey;

  const OrderList({
    super.key,
    required this.nameController,
    required this.nodeEditorKey,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<SeeProcessBloc, SeeProcessState>(
      buildWhen: (previous, current) =>
          previous.selectedProcess != current.selectedProcess ||
          previous.process?.name != current.process?.name ||
          previous.process?.tasks != current.process?.tasks ||
          previous.sequences != current.sequences,
      builder: (context, state) {
        if (state.selectedProcess != null && state.process != null) {
          nameController.text = state.process!.name;
          final machines = state.process!.tasks
                  ?.map((t) => MachineTypeEntity(
                        id: t.machineTypeId,
                        name: t.machineName ?? '',
                        description: t.description ?? '',

                      ))
                  .toList() ??
              [];
          final connections = (state.process!.dependencies ?? [])
              .map((dep) => Connection(dep.predecessor_id, dep.successor_id))
              .toList();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            nodeEditorKey.currentState?.loadNodesAndConnections(machines, connections);
          });
        }

        Widget dropdown = PopupMenuButton<int>(
          tooltip: 'Ver rutas de proceso',
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (int selectedId) async {
            BlocProvider.of<SeeProcessBloc>(context).selectSequence(selectedId);

            await Future.delayed(const Duration(milliseconds: 200));
            final process = BlocProvider.of<SeeProcessBloc>(context).state.process;
            if (process != null && process.tasks != null) {
              final machines = process.tasks!
                  .map((t) => MachineTypeEntity(
                        id: t.id,
                        name: t.machineName ?? '',
                        description: t.description ?? '',
                      ))
                  .toList();

              final connections = (process.dependencies ?? [])
                  .map((dep) => Connection(dep.predecessor_id, dep.successor_id))
                  .toList();

              nodeEditorKey.currentState?.loadNodesAndConnections(machines, connections);
            }
          },
          itemBuilder: (context) {
            final sequences = state.sequences ?? [];

            if (sequences.isEmpty) {
              return [
                const PopupMenuItem<int>(
                  enabled: false,
                  child: Text('No hay rutas registradas'),
                )
              ];
            }

            return sequences.map((seq) {
              return PopupMenuItem<int>(
                value: seq.id!,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(seq.name)),
                    GestureDetector(
                      onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('¿Eliminar ruta?'),
                          content: Text('¿Estás seguro de eliminar "${seq.name}"?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Eliminar'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        final bloc = BlocProvider.of<SeeProcessBloc>(context);
                        bloc.deleteSequence(seq.id!);

                        // Cierra el popup después de eliminar
                        Navigator.of(context).pop(); // Cierra el PopupMenu

                     
                      }
                    },

                      child: AbsorbPointer(
                        child: Icon(Icons.delete, color: colorScheme.error),
                      ),
                    ),
                  ],
                ),
              );

            }).toList();
          },
          child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.list),
            const SizedBox(width: 6),
            Text(
              state.selectedProcess != null
                  ? state.process?.name ?? 'Seleccionar'
                  : 'Seleccione una ruta',
              style: TextStyle(
                color: state.selectedProcess != null
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontStyle: state.selectedProcess != null ? null : FontStyle.italic,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_drop_down, color: colorScheme.primary),
          ],
        ),

        );


        if (state is SeeProcessInitialState) {
          BlocProvider.of<SeeProcessBloc>(context).retrieveSequences();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300), // ajusta si quieres más
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withOpacity(0.15),
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                      border: Border.all(
                        color: colorScheme.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: dropdown,
                  ),
                ),


                if (state.selectedProcess != null)
                  Expanded(
                    child: SequenceEditorPanel(
                      nameController: nameController,
                      onSave: () {},
                      machines: state.process?.tasks
                              ?.map((t) => MachineTypeEntity(
                                    id: t.machineTypeId,
                                    name: t.machineName ?? '',
                                    description: t.description ?? '',

                                  ))
                              .toList() ??
                          [],
                      nodeEditorKey: nodeEditorKey,
                      onlyGraph: true,

                    ),
                  ),
                if (state.selectedProcess == null)
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 400),

                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            'Ninguna orden seleccionada',
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

