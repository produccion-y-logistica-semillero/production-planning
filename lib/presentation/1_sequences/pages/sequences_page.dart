// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/entities/process_entity.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_state.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/graph_editor.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/orders_list.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/sequence_editor_panel.dart';
import 'package:production_planning/presentation/1_sequences/widgets/low_order_widgets/button_mode.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/machines_list.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/add_order.dart';

class SequencesPage extends StatefulWidget {
  SequencesPage({super.key});

  @override
  State<SequencesPage> createState() => _SequencesPageState();
}

class _SequencesPageState extends State<SequencesPage> {
  final TextEditingController _sequenceNameController = TextEditingController();
  final GlobalKey<NodeEditorState> nodeEditorKey = GlobalKey<NodeEditorState>();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SeeProcessBloc>(
      create: (context) => GetIt.instance.get<SeeProcessBloc>(),
      child: Scaffold(
        appBar: getAppBar(),
        body: BlocBuilder<SequencesBloc, SequencesState>(
            builder: (context, state) {
          Widget machinesContent =
              const Center(child: CircularProgressIndicator());

          if (state is SequencesInitialState)
            BlocProvider.of<SequencesBloc>(context).retrieveSequencesMachine();
          if (state is SequencesMachineFailure)
            machinesContent = const Center(child: Text("Error fetching"));
          if (state.machines != null) {
            machinesContent = MachinesList(
              machineTypes: state.machines!,
              onSelectMachine: (machine) {
                BlocProvider.of<SequencesBloc>(context).selectMachine(machine);
                nodeEditorKey.currentState?.addNodeForMachine(machine);
              },
            );
          }
          final machinesList = machinesContent;

          final Widget board;
          if (state.isNewOrder) {
            board = SequenceEditorPanel(
              nameController: _sequenceNameController,
              onSave: () {
                final name = _sequenceNameController.text;
                if (name.isNotEmpty) {
                  _onSaveOrder(context, name);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Por favor ingresa un nombre para la secuencia')),
                  );
                }
              },
              machines: state.machines ?? [],
              nodeEditorKey: nodeEditorKey,
            );
          } else {
            board = OrderList(
              nameController: _sequenceNameController,
              nodeEditorKey: nodeEditorKey,
            );
          }

          return Row(
            children: [
              IconButton(
                  onPressed: () => printInfo(context,
                      title: 'Secuencias',
                      content:
                          'Una secuencia se refiere al proceso de fabricacion de un producto, aca se define la secuencia de maquinas por las que se debe pasar para la fabricacion, el orden representa pre requisitos, y en cada paso por una maquina, o "tarea" se especifica cuanto tiempo en promedio se requiere en esa maquina, por ejemplo, la produccion de pan:\n\nTarea 1: Maquina de mezclado, 20min\nTarea 2: Camara de reposo, 10 min\nTarea 3: Maquina divisora, 4 min\nTarea 5: Maquina de formado, 15 min\nTarea 6: Maquina de horneado, 1 hora\nTarea 7: Maquina de enfriado 40 min'),
                  icon: const Icon(Icons.info)),
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      if (state.isNewOrder)
                        Expanded(
                          flex: 2,
                          child: machinesList,
                        ),
                      Expanded(
                        flex: 1,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ButtonMode(
                                callback: state.isNewOrder
                                    ? () =>
                                        BlocProvider.of<SequencesBloc>(context)
                                            .useMode(false)
                                    : () =>
                                        BlocProvider.of<SequencesBloc>(context)
                                            .useMode(true),
                                labelText: state.isNewOrder
                                    ? "Ver Secuencias"
                                    : "Nueva Ruta de proceso",
                                icon: Icons.roller_shades_closed_outlined,
                                horizontalPadding: 30),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(flex: 2, child: board),
            ],
          );
        }),
      ),
    );
  }

  void _onSaveOrder(BuildContext context, String name) {
    final nodes = nodeEditorKey.currentState?.getNodes() ?? [];
    final connections = nodeEditorKey.currentState?.getConnections() ?? [];
    BlocProvider.of<SequencesBloc>(context)
        .saveProcess(name, nodes, connections);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ruta de proceso creada'),
        content:
            const Text('La ruta de proceso ha sido guardada exitosamente.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              GetIt.instance.get<SequencesBloc>().useMode(false);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }
}
