// lib/presentation/2_orders/pages/new_order_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/add_job.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/utils/task_time_utils.dart';

/// One station (machine type) of the order, with ALL its machines.
class _OrderStation {
  final String name;
  final List<MachineEntity> machines;
  const _OrderStation(this.name, this.machines);
}

/// Every station used by any job of the order, with every machine it has —
/// not only the machines some job currently has selected. Machines are in
/// id order, stations in machine-type-id order.
Map<int, _OrderStation> _orderStations(NewOrdersState state) {
  final names = <int, String>{};
  final machines = <int, Map<int, MachineEntity>>{};
  for (final job in state.jobs) {
    final jobState = job.stateKey.currentState;
    if (jobState == null) continue;
    names.addAll(jobState.getStationNames());
    jobState.getStationMachines().forEach((typeId, list) {
      final byId = machines.putIfAbsent(typeId, () => {});
      for (final m in list) {
        if (m.id != null) byId[m.id!] = m;
      }
    });
  }
  final typeIds = machines.keys.toList()..sort();
  return {
    for (final typeId in typeIds)
      typeId: _OrderStation(
        names[typeId] ?? 'Estación $typeId',
        machines[typeId]!.values.toList()
          ..sort((a, b) => a.id!.compareTo(b.id!)),
      ),
  };
}

/// Where each machine's entry comes from (its own, a sibling's, or none),
/// using the same rule the scheduler applies — see [stationDefaultSource].
Map<String, String?> _entrySources(
    Map<int, _OrderStation> stations, Set<String> namesWithOwnEntry) {
  final result = <String, String?>{};
  for (final station in stations.values) {
    result.addAll(stationDefaultSource(station.machines, namesWithOwnEntry));
  }
  return result;
}

class NewOrderPage extends StatelessWidget {
  final int? editOrderId;

  const NewOrderPage({super.key, this.editOrderId});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(editOrderId != null
            ? 'Editar Programa de Producción'
            : 'Crear Nuevo Programa de Produccion'),
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
                if (editOrderId != null) {
                  bloc.loadOrderForEdit(editOrderId!);
                } else {
                  bloc.retrieveSequences();
                }
                return const Center(child: CircularProgressIndicator());
              }

              if (state is NewOrdersFailureState) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text('Error al cargar los datos',
                          style: TextStyle(color: colorScheme.error, fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('Verifique la conexión a la base de datos',
                          style: TextStyle(color: colorScheme.onSurface)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          if (editOrderId != null) {
                            bloc.loadOrderForEdit(editOrderId!);
                          } else {
                            bloc.retrieveSequences();
                          }
                        },
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                );
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
                    if (state is NewOrdersState)
                      _buildDateModeToggle(context, bloc, state, colorScheme),
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
                      onPressed: () =>
                          _showMachineInitialStatesDialog(context, state, colorScheme),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Definir estado inicial de máquinas'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (!_validateForm(state)) {
                          _showValidationDialog(context, colorScheme);
                        } else {
                          if (editOrderId != null) {
                            bloc.updateOrder(editOrderId!);
                          } else {
                            bloc.saveOrder();
                          }
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
                      child: Text(editOrderId != null
                          ? 'Guardar Cambios'
                          : 'Crear programa de produccion'),
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
  // Date-registration mode toggle
  // ---------------------------------------------------------------------------

  Widget _buildDateModeToggle(
    BuildContext context,
    NewOrderBloc bloc,
    NewOrdersState state,
    ColorScheme colorScheme,
  ) {
    final leadTimeController =
        TextEditingController(text: state.leadTimeDays.toString());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SegmentedButton<DateRegistrationMode>(
                segments: const [
                  ButtonSegment(
                    value: DateRegistrationMode.manual,
                    label: Text('Manual'),
                    icon: Icon(Icons.edit_calendar_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: DateRegistrationMode.automatic,
                    label: Text('Automático'),
                    icon: Icon(Icons.auto_awesome_rounded, size: 16),
                  ),
                ],
                selected: {state.dateMode},
                onSelectionChanged: (selection) =>
                    bloc.setDateMode(selection.first),
              ),
              if (state.dateMode == DateRegistrationMode.automatic) ...[
                const SizedBox(width: 12),
                const Text('Plazo (días):'),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: leadTimeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (value) {
                      final days = int.tryParse(value.trim());
                      if (days != null && days > 0) {
                        bloc.setLeadTimeDays(days);
                      }
                    },
                    onEditingComplete: () {
                      final days =
                          int.tryParse(leadTimeController.text.trim());
                      if (days != null && days > 0) {
                        bloc.setLeadTimeDays(days);
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
          if (state.dateMode == DateRegistrationMode.automatic) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _selectOrderAutomaticHour(
                  context,
                  'Hora de inicio',
                  state.automaticStartHour,
                  bloc.setAutomaticStartHour,
                  colorScheme,
                ),
                const SizedBox(width: 24),
                _selectOrderAutomaticHour(
                  context,
                  'Hora de entrega',
                  state.automaticDueHour,
                  bloc.setAutomaticDueHour,
                  colorScheme,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Aplican a todos los jobs de esta orden que no tengan su '
              'propia hora. Si se dejan vacías, se usa la hora actual.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Order-wide hour picker for automatic mode — mirrors the per-job
  /// `_selectAutomaticHour` in `add_job.dart`, but writes to the bloc's
  /// order-level default instead of a single job's override.
  Widget _selectOrderAutomaticHour(
    BuildContext context,
    String label,
    TimeOfDay? hour,
    ValueChanged<TimeOfDay?> onPicked,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: TextStyle(color: colorScheme.onSurface)),
        TextButton(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: hour ?? TimeOfDay.now(),
            );
            if (picked != null) onPicked(picked);
          },
          child: hour == null
              ? const Text('Hora actual')
              : Text("${hour.hour.toString().padLeft(2, '0')}:"
                  "${hour.minute.toString().padLeft(2, '0')}"),
        ),
        if (hour != null)
          IconButton(
            icon: const Icon(Icons.clear, size: 16),
            tooltip: 'Usar hora actual',
            onPressed: () => onPicked(null),
          ),
      ],
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

    // EVERY machine of every station the order uses, grouped by station —
    // not only those some job has selected — so each one can get its own
    // matrix. A machine without one uses its station's default: the matrix
    // of the lowest-id sibling that has one (same rule as the scheduler).
    final stations = _orderStations(state);
    final stationOf = <String, String>{};
    final machineNames = <String>[];
    for (final station in stations.values) {
      for (final m in station.machines) {
        if (stationOf.containsKey(m.name)) continue;
        stationOf[m.name] = station.name;
        machineNames.add(m.name);
      }
    }
    // Machines selected in a job but whose station list is not loaded yet.
    for (final job in state.jobs) {
      for (final name
          in job.stateKey.currentState?.getMachineNames() ?? const <String>[]) {
        if (!stationOf.containsKey(name)) {
          stationOf[name] = '';
          machineNames.add(name);
        }
      }
    }
    if (machineNames.isEmpty) {
      machineNames.add('(seleccione máquinas primero)');
    }

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
      // A machine with no matrix of its own starts from the one it inherits,
      // so what the user sees is what the scheduler would use.
      final String? source =
          _entrySources(stations, existingMatrices.keys.toSet())[machine];
      final matrix = existingMatrices[machine] ??
          (source == null ? null : existingMatrices[source]) ??
          {};
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

            void copyFrom(String source) {
              final matrix = existingMatrices[source] ?? {};
              setState(() {
                for (final r in jobStates) {
                  for (final c in jobStates) {
                    final val = matrix[r]?[c] ?? 0;
                    controllers[r]![c]!.text = val == 0 ? '' : val.toString();
                  }
                }
              });
            }

            final sources =
                _entrySources(stations, existingMatrices.keys.toSet());
            final String? selectedSource = sources[selectedMachine];
            final String originNote = existingMatrices
                    .containsKey(selectedMachine)
                ? 'Esta máquina tiene matriz propia.'
                : selectedSource != null
                    ? 'Sin matriz propia: usa por defecto la de '
                        '"$selectedSource" (misma estación). Al guardar, '
                        'esta máquina pasa a tener matriz propia.'
                    : 'Sin matriz: el alistamiento en esta máquina será 0 '
                        'hasta que se registre una (aquí o en otra máquina '
                        'de su estación).';
            final copySources = existingMatrices.keys
                .where((m) => m != selectedMachine)
                .toList()
              ..sort();

            return AlertDialog(
              title: const Text("Matriz de tiempos de alistamiento"),
              content: SizedBox(
                width: double.maxFinite,
                height: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedMachine,
                            decoration:
                                const InputDecoration(labelText: 'Máquina'),
                            isExpanded: true,
                            items: machineNames.map((m) {
                              final isSaved = existingMatrices.containsKey(m);
                              final inherited = !isSaved && sources[m] != null;
                              final station = stationOf[m] ?? '';
                              return DropdownMenuItem<String>(
                                value: m,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        station.isEmpty ? m : '$station · $m',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSaved) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.check_circle,
                                          color: Colors.green, size: 16),
                                    ],
                                    if (inherited) ...[
                                      const SizedBox(width: 6),
                                      Text('(hereda de ${sources[m]})',
                                          style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12)),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) switchMachine(v);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          tooltip: 'Copiar matriz de otra máquina',
                          enabled: copySources.isNotEmpty,
                          icon: const Icon(Icons.content_copy),
                          onSelected: copyFrom,
                          itemBuilder: (_) => copySources
                              .map((m) => PopupMenuItem<String>(
                                    value: m,
                                    child: Text('Copiar matriz de $m'),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        originNote,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tiempo en minutos para cambiar del estado (Fila) al estado (Columna). La diagonal (mismo estado fila/columna) también puede tener un valor propio.',
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
  // Machine initial states dialog
  // ---------------------------------------------------------------------------

  /// The state (A-J) each candidate machine starts this program in, before
  /// its first job. Without one, that machine's first job pays no setup —
  /// there is nothing to compare it against, same as before this existed.
  void _showMachineInitialStatesDialog(
    BuildContext context,
    NewOrderState state,
    ColorScheme colorScheme,
  ) {
    if (state is! NewOrdersState) return;

    // Every machine of every station the order uses (see _orderStations),
    // plus any selected machine whose station list is not loaded yet.
    final stations = _orderStations(state);
    final stationOf = <String, String>{};
    final machineNames = <String>[];
    for (final station in stations.values) {
      for (final m in station.machines) {
        if (stationOf.containsKey(m.name)) continue;
        stationOf[m.name] = station.name;
        machineNames.add(m.name);
      }
    }
    for (final job in state.jobs) {
      for (final name
          in job.stateKey.currentState?.getMachineNames() ?? const <String>[]) {
        if (!stationOf.containsKey(name)) {
          stationOf[name] = '';
          machineNames.add(name);
        }
      }
    }

    if (machineNames.isEmpty) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Estado inicial de máquinas'),
          content: const Text(
              'Seleccione al menos una máquina en un job antes de definir '
              'su estado inicial.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      return;
    }

    const letters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'];
    final bloc = BlocProvider.of<NewOrderBloc>(context);
    final current =
        Map<String, String>.from(state.machineInitialStates ?? {});

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Estado inicial de máquinas'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'La letra que cada máquina tiene antes de que llegue su '
                      'primer job de esta orden. Se usa para calcular el '
                      'alistamiento del primer job en esa máquina.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    for (final machine in machineNames)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Builder(builder: (_) {
                                final station = stationOf[machine] ?? '';
                                final source = _entrySources(stations,
                                    current.keys.toSet())[machine];
                                final inherited = !current.containsKey(machine) &&
                                    source != null;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(station.isEmpty
                                        ? machine
                                        : '$station · $machine'),
                                    if (inherited)
                                      Text(
                                        'Por defecto: ${current[source]} '
                                        '(hereda de $source)',
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12),
                                      ),
                                  ],
                                );
                              }),
                            ),
                            DropdownButton<String?>(
                              value: current[machine],
                              hint: const Text('Sin estado'),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Sin estado'),
                                ),
                                ...letters.map((l) => DropdownMenuItem<String?>(
                                    value: l, child: Text(l))),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  if (value == null) {
                                    current.remove(machine);
                                  } else {
                                    current[machine] = value;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cerrar'),
              ),
              ElevatedButton(
                onPressed: () {
                  bloc.setMachineInitialStates(current);
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  bool _validateForm(NewOrderState state) {
    if (state is NewOrdersState && state.jobs.isNotEmpty) {
      final datesAreManual = state.dateMode == DateRegistrationMode.manual;
      for (final job in state.jobs) {
        if (job.priorityController?.text.isEmpty ?? true) return false;
        if (datesAreManual && job.availableDate == null) return false;
        if (datesAreManual && job.dueDate == null) return false;
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