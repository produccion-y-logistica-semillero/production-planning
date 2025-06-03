import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_state.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/sequence_editor_panel.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/graph_editor.dart';

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
                .toList() ?? [];
            final connections = (state.process!.dependencies ?? [])
                .map((dep) => Connection(dep.predecessor_id, dep.successor_id))
                .toList();

            WidgetsBinding.instance.addPostFrameCallback((_) {
              nodeEditorKey.currentState?.loadNodesAndConnections(machines, connections);
            });
        }

        
        Widget dropdown = DropdownButton<int>(
          borderRadius: BorderRadius.circular(12),
          value: state.selectedProcess,
          hint: Text(
            (state.sequences == null || state.sequences!.isEmpty)
                ? 'No hay rutas de proceso registradas'
                : 'Vea sus rutas de proceso registradas',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          items: (state.sequences ?? []).isEmpty
              ? [
                  DropdownMenuItem<int>(
                    value: null,
                    enabled: false,
                    child: Text(
                      'No hay rutas de proceso registradas',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                ]
              : (state.sequences ?? []).map((process) {
                  return DropdownMenuItem<int>(
                    value: process.id,
                    child: Text(
                      process.name,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  );
                }).toList(),
                onChanged: (state.sequences == null || state.sequences!.isEmpty)
                    ? null
                    : (value) async {
                        if (value != null) {
                          BlocProvider.of<SeeProcessBloc>(context).selectSequence(value);

                          await Future.delayed(const Duration(milliseconds: 200));
                          final process = BlocProvider.of<SeeProcessBloc>(context).state.process;
                          if (process != null && process.tasks != null) {
                            final machines = process.tasks!
                                .map((t) => MachineTypeEntity(
                                      id: t.machineTypeId,
                                      name: t.machineName ?? '',
                                      description: t.description ?? '',
                                    ))
                                .toList();

                            final connections = (process.dependencies ?? [])
                              .map((dep) => Connection(dep.predecessor_id, dep.successor_id))
                              .toList();

                            
                            print('--- CONEXIONES AL SELECCIONAR DEL DROPDOWN ---');
                            for (final conn in connections) {
                              print('predecessor_id: ${conn.source}, successor_id: ${conn.target}');
                            }

                            nodeEditorKey.currentState?.loadNodesAndConnections(machines, connections);
                          }
                        }
                      },
          isExpanded: true,
          underline: Container(
            height: 0,
            color: Colors.transparent,
          ),
          icon: Icon(Icons.arrow_drop_down, color: colorScheme.primary),
          dropdownColor: colorScheme.surface,
        );

        if (state is SeeProcessInitialState) {
          BlocProvider.of<SeeProcessBloc>(context).retrieveSequences();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
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
                  child: Center(child: dropdown),
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
                    ),
                  ),
                if (state.selectedProcess == null)
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(
                        maxHeight: 400,
                      ),
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