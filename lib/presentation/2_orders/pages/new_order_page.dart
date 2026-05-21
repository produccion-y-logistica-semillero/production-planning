// lib/presentation/2_orders/pages/new_order_page.dart
//
// Fix (this version): DropdownMenuItem child used Expanded inside an
// unbounded Row, which Flutter cannot lay out and throws an infinite
// layout-error loop.  Replaced with mainAxisSize.min + plain Text.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/add_job.dart';
import 'package:production_planning/shared/functions/functions.dart';

class NewOrderPage extends StatelessWidget {
  const NewOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Nuevo Programa de Produccion'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: BlocListener<NewOrderBloc, NewOrderState>(
          listener: (context, state) {
            if (state is NewOrdersState && state.justSaved != null) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (subcontext) => AlertDialog(
                  title: Text(
                    state.justSaved! ? "Guardado!!" : "Error",
                    style: TextStyle(
                      color: state.justSaved!
                          ? colorScheme.primary
                          : colorScheme.error,
                    ),
                  ),
                  content: Text(
                    state.justSaved!
                        ? "La orden ha sido guardada exitosamente"
                        : "Hubo un error guardando la orden",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(subcontext).pop();
                        Navigator.of(context).pop(state.justSaved);
                      },
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );
            }
          },
          child: BlocBuilder<NewOrderBloc, NewOrderState>(
            builder: (context, state) {
              final bloc = BlocProvider.of<NewOrderBloc>(context);

              if (state is NewOrdersInitialState) {
                bloc.retrieveSequences();
                return const Center(child: CircularProgressIndicator());
              }

              final List<AddJobWidget> jobWidgets =
                  state is NewOrdersState ? state.jobs : [];

              return Center(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info),
                          onPressed: () => printInfo(
                            context,
                            title: 'Crear orden',
                            content:
                                'La creacion de una orden implica seleccionar '
                                'los productos que deben ser fabricados, la '
                                'prioridad que se tiene para fabricarlos, desde '
                                'cuando se tiene la disponibilidad para '
                                'fabricarlos (por ejemplo, por insumos), y cual '
                                'es la fecha limite.\n\nUn producto esta '
                                'relacionado con una secuencia, pues una '
                                'secuencia es la secuencia de produccion para '
                                'producir un producto.',
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(children: jobWidgets),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => bloc.addJob(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Agregar Job'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          _showMatrixDialog(context, state, colorScheme),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text(
                          'Definir matriz de tiempos de alistamiento'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (!_validateForm(state)) {
                          _showValidationDialog(context, colorScheme);
                        } else {
                          bloc.saveOrder();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.secondary,
                        foregroundColor: colorScheme.onSecondary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Crear programa de produccion'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Matrix dialog
  // ---------------------------------------------------------------------------

  void _showMatrixDialog(
    BuildContext context,
    NewOrderState state,
    ColorScheme colorScheme,
  ) {
    if (state is! NewOrdersState) return;

    final machineNameSet = <String>{};
    for (final job in state.jobs) {
      machineNameSet
          .addAll(job.stateKey.currentState?.getMachineNames() ?? []);
    }
    final machineNames = machineNameSet.isEmpty
        ? ['(seleccione máquinas primero)']
        : (machineNameSet.toList()..sort());

    final stateSet = <String>{};
    for (final job in state.jobs) {
      stateSet.addAll(
          (job.stateKey.currentState?.getMachineFinalStates() ?? {}).values);
    }
    final jobStates = stateSet.isEmpty
        ? ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J']
        : (stateSet.toList()..sort());

    final bloc = BlocProvider.of<NewOrderBloc>(context);
    final existingMatrices = Map<String, Map<String, Map<String, int>>>.from(state.setupTimeMatrix ?? {});

    String selectedMachine = machineNames.first;
    final controllers = <String, Map<String, TextEditingController>>{};

    void buildControllers(String machine) {
      final matrix = existingMatrices[machine] ?? {};
      for (final r in jobStates) {
        controllers[r] = {};
        for (final c in jobStates) {
          final val = matrix[r]?[c] ?? 0;
          controllers[r]![c] = TextEditingController(text: val == 0 ? '' : val.toString());
        }
      }
    }
    buildControllers(selectedMachine);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            void flushToModel() {
              final newMatrix = <String, Map<String, int>>{};
              for (final r in jobStates) {
                newMatrix[r] = {};
                for (final c in jobStates) {
                  final text = controllers[r]![c]!.text;
                  newMatrix[r]![c] = int.tryParse(text) ?? 0;
                }
              }
              existingMatrices[selectedMachine] = newMatrix;
              bloc.setSetupTimeMatrix(existingMatrices);
            }

            void switchMachine(String name) {
              setState(() {
                selectedMachine = name;
                buildControllers(name);
              });
            }

            return AlertDialog(
              title: const Text("Matriz de tiempos de alistamiento"),
              content: SizedBox(
                width: double.maxFinite,
                height: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedMachine,
                      decoration: const InputDecoration(labelText: 'Máquina'),
                      isExpanded: true,
                      items: machineNames.map((m) {
                        final isSaved = existingMatrices.containsKey(m);
                        return DropdownMenuItem<String>(
                          value: m,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m),
                              if (isSaved) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) switchMachine(v);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tiempo en minutos para cambiar del estado (Fila) al estado (Columna).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            columns: [
                              const DataColumn(label: SizedBox(width: 24, child: Text(''))),
                              ...jobStates.map((label) => DataColumn(
                                label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                              )),
                            ],
                            rows: jobStates.map((r) => DataRow(
                              cells: [
                                DataCell(Text(r, style: const TextStyle(fontWeight: FontWeight.bold))),
                                ...jobStates.map((c) {
                                  return DataCell(
                                    TextField(
                                      controller: controllers[r]![c],
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }),
                              ],
                            )).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text("Cerrar"),
                ),
                ElevatedButton(
                  onPressed: () {
                    flushToModel();
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Matriz de alistamiento guardada para $selectedMachine')),
                    );
                  },
                  child: const Text("Guardar"),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  bool _validateForm(NewOrderState state) {
    if (state is NewOrdersState && state.jobs.isNotEmpty) {
      for (final job in state.jobs) {
        if (job.priorityController?.text.isEmpty ?? true) return false;
        if (job.quantityController?.text.isEmpty ?? true) return false;
        if (job.availableDate == null) return false;
        if (job.dueDate == null) return false;
        if (job.selectedSequence == null) return false;
      }
      return true;
    }
    return false;
  }

  void _showValidationDialog(BuildContext context, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (subcontext) => AlertDialog(
        title: Text("Campos Incompletos",
            style: TextStyle(color: colorScheme.error)),
        content: const Text(
            "Asegúrese de llenar todos los campos de todos los jobs "
            "antes de crear el programa de producción."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(subcontext).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}