import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/shared/widgets/hour_text_input.dart';
import 'package:production_planning/shared/widgets/input_field_custom.dart';
import 'package:production_planning/presentation/1_sequences/request_models/new_task_model.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_state.dart';
import 'package:production_planning/presentation/1_sequences/widgets/low_order_widgets/add_machines_successful.dart';
import 'package:production_planning/presentation/1_sequences/widgets/low_order_widgets/error_add_machines.dart';
import 'package:production_planning/presentation/1_sequences/widgets/low_order_widgets/task_container.dart';

class AddOrderForm extends StatelessWidget {
  final TextEditingController _nameOrder = TextEditingController();
  final List<MachineTypeEntity> selectedMachines;
  final void Function(String name) onSave;
  final SequencesState state;
  final TextEditingController descController = TextEditingController();
  final TextEditingController hourController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  AddOrderForm({
    super.key,
    required this.selectedMachines,
    required this.onSave,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Campo para el nombre del trabajo
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 5),
                margin: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: TextField(
                  controller: _nameOrder,
                  decoration: InputDecoration(
                    labelText: 'Nombre del trabajo',
                    labelStyle: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Contenedor para las máquinas seleccionadas
              Container(
                constraints: const BoxConstraints(maxHeight: 500),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(0.15),
                      spreadRadius: 2,
                      blurRadius: 7,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(
                    color: colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    _scrollController.jumpTo(_scrollController.offset - details.delta.dx);
                  },
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _scrollController,
                    child: Row(
                      children: _buildMachineList(state.selectedMachines, context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Botón Guardar
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _saveOrder(_nameOrder.text, selectedMachines, context);
                    },
                    label: Text(
                      "Guardar",
                      style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 16),
                    ),
                    icon: Icon(
                      Icons.save,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      minimumSize: const Size(140, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (state.isNoMachinesModalVisible)
          _buildOverlay(
            NoMachinesSelectedModal(
              onClose: () => BlocProvider.of<SequencesBloc>(context).modelChanged(false),
            ),
            context,
          ),
        if (state.isSuccessModalVisible)
          _buildOverlay(
            SuccessModal(
              onClose: () => BlocProvider.of<SequencesBloc>(context).machinesSuccessModalChanged(false),
            ),
            context,
          ),
      ],
    );
  }

  // Función para construir la lista de máquinas con flechas intercaladas
  List<Widget> _buildMachineList(List<NewTaskModel>? machines, BuildContext context) {
    List<Widget> machineWidgets = [];

    if (machines == null) {
      machineWidgets.add(
        const SizedBox(height: 500),
      );
    } else {
      for (int i = 0; i < machines.length; i++) {
        machineWidgets.add(
          TaskContainer(
            task: machines[i],
            number: i + 1,
            onDeleteCallback: () => BlocProvider.of<SequencesBloc>(context).taskRemoved(i),
            callback: () {
              showDialog(
                context: context,
                builder: (dialogContext) {
                  return Dialog(
                    child: SizedBox(
                      height: 350,
                      width: MediaQuery.of(context).size.width - 900,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Maquina ${machines[i].machineName}'),
                          const SizedBox(height: 10),
                          InputFieldCustom(
                            sizedBoxWidth: 30,
                            maxLines: 5,
                            title: "Descripcion",
                            hintText: "",
                            controller: descController,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Tiempo: "),
                              HourTextInput(controller: hourController),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(dialogContext).pop(),
                                child: const Text("Cancelar"),
                              ),
                              TextButton(
                                onPressed: () {
                                  BlocProvider.of<SequencesBloc>(context).tsaskUpdated(i, descController.text, hourController.text);
                                  hourController.clear();
                                  descController.clear();
                                  Navigator.of(dialogContext).pop();
                                },
                                child: const Text("Guardar"),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );

        if (i < machines.length - 1) {
          machineWidgets.add(
            const Icon(
              Icons.arrow_forward,
              size: 30,
              color: Colors.grey,
            ),
          );
        }
      }
    }

    return machineWidgets;
  }

  // Función para guardar la orden
  void _saveOrder(String name, List<MachineTypeEntity> selectedMachines, BuildContext context) {
    if (name.isNotEmpty) {
      onSave(name);
    } else {
      BlocProvider.of<SequencesBloc>(context).modelChanged(true);
    }
  }

  // Función para mostrar los modales sobre toda la pantalla
  Widget _buildOverlay(Widget modal, BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: () {
              BlocProvider.of<SequencesBloc>(context).modelChanged(false);
              BlocProvider.of<SequencesBloc>(context).machinesSuccessModalChanged(false);
            },
            child: const SizedBox(
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          Center(child: modal),
        ],
      ),
    );
  }
}
