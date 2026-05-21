// lib/presentation/2_orders/widgets/high_order/add_job.dart
//
// Changes from previous version:
//   • _showStationTimeDialog no longer shows the "Tiempo de Alistamiento" field.
//     That changeover cost now comes exclusively from the setup-time matrix.
//   • The 'preparation' key is still stored (as 0) so downstream code that
//     reads _explicitTaskMachineMinutes['preparation'] doesn't break.
//   • getMachineNames() and getMachineFinalStates() public getters added
//     (were already in the version provided, kept as-is).
//   • Everything else is identical to the version provided by the user.

import 'package:dartz/dartz.dart' as dartz;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_standard_times.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_bloc.dart';

// ignore: must_be_immutable
class AddJobWidget extends StatefulWidget {
  DateTime? availableDate;
  DateTime? dueDate;
  TimeOfDay? availableHour;
  TimeOfDay? dueHour;
  final TextEditingController? priorityController;
  final TextEditingController? quantityController;
  final TextEditingController? idController;
  final List<dartz.Tuple2<int, String>> sequences;
  final int index;
  int? selectedSequence;

  final GlobalKey<AddJobState> stateKey;

  AddJobWidget._({
    required this.stateKey,
    required this.availableDate,
    required this.dueDate,
    required this.availableHour,
    required this.dueHour,
    required this.priorityController,
    required this.quantityController,
    required this.idController,
    required this.index,
    required this.sequences,
  }) : super(key: stateKey);

  factory AddJobWidget({
    required DateTime? availableDate,
    required DateTime? dueDate,
    required TimeOfDay? availableHour,
    required TimeOfDay? dueHour,
    required TextEditingController? priorityController,
    required TextEditingController? quantityController,
    required TextEditingController? idController,
    required int index,
    required List<dartz.Tuple2<int, String>> sequences,
    GlobalKey<AddJobState>? stateKey,
  }) {
    final key = stateKey ?? GlobalKey<AddJobState>();
    return AddJobWidget._(
      stateKey: key,
      availableDate: availableDate,
      dueDate: dueDate,
      availableHour: availableHour,
      dueHour: dueHour,
      priorityController: priorityController,
      quantityController: quantityController,
      idController: idController,
      index: index,
      sequences: sequences,
    );
  }

  Map<int, int> getPreemptionMatrix() {
    return stateKey.currentState?._preemptionMatrix ?? {};
  }

  @override
  AddJobState createState() {
    return AddJobState();
  }
}

class AddJobState extends State<AddJobWidget> {
  int? selectedSequenceValue;
  DateTime? availableDate;
  DateTime? dueDate;
  TimeOfDay? availableHour;
  TimeOfDay? dueHour;

  SequenceEntity? _sequenceDetails;
  bool _loadingStations = false;
  final Map<int, List<MachineEntity>> _machinesByType = {};
  final Map<int, MachineEntity?> _selectedMachines = {};
  final Map<int, MachineStandardTimes> _stationTimes = {};
  final Map<int, Map<int, Map<String, int>>> _explicitTaskMachineMinutes = {};
  final Map<int, int> _preemptionMatrix = {};

  final Map<int, String> _machineFinalStates = {};
  final List<String> _letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'
  ];

  // ── public getters used by the matrix dialog ──────────────────────────────

  Map<int, int> getPreemptionMatrix() => _preemptionMatrix;

  Map<int, int> getSelectedMachines() {
    final map = <int, int>{};
    _selectedMachines.forEach((key, value) {
      if (value != null && value.id != null) map[key] = value.id!;
    });
    return map;
  }

  Map<int, int> getStationProcessingMinutes() {
    final res = <int, int>{};
    _stationTimes.forEach((machineTypeId, times) {
      res[machineTypeId] = times.processing.inMinutes;
    });
    return res;
  }

  Map<int, Map<int, Map<String, int>>> getExplicitTaskMachineMinutes() {
    return _explicitTaskMachineMinutes.map((taskId, machines) => MapEntry(
        taskId,
        machines.map((machineId, times) =>
            MapEntry(machineId, Map<String, int>.from(times)))));
  }

  List<TaskEntity>? getSequenceTasks() => _sequenceDetails?.tasks;

  String? getJobState() {
    if (_machineFinalStates.isEmpty) return null;
    final values = _machineFinalStates.values.toList();
    return values.isNotEmpty ? values.first : null;
  }

  /// Returns the display names of all currently selected machines.
  /// Used by the matrix dialog to populate its machine drop-down.
  List<String> getMachineNames() {
    final names = <String>{};
    _selectedMachines.forEach((_, machine) {
      if (machine != null && machine.name.isNotEmpty) {
        names.add(machine.name);
      }
    });
    return names.toList();
  }

  /// Returns Map<machineTypeId, stateLetter> for the "Estado dejado" dropdowns.
  /// Used by the matrix dialog to determine the row/column labels.
  Map<int, String> getMachineFinalStates() =>
      Map<int, String>.from(_machineFinalStates);

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    availableDate = widget.availableDate;
    dueDate = widget.dueDate;
    availableHour = widget.availableHour;
    dueHour = widget.dueHour;
    selectedSequenceValue = widget.selectedSequence;
    if (selectedSequenceValue != null) {
      _loadSequence(selectedSequenceValue!);
    }
  }

  // ── date / time pickers ───────────────────────────────────────────────────

  Future<void> _selectDate(BuildContext context, String label) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (label == 'Seleccione fecha de disponibilidad') {
          final currentHour = availableHour ?? widget.availableHour;
          widget.availableDate = DateTime(
            picked.year, picked.month, picked.day,
            currentHour?.hour ?? 0, currentHour?.minute ?? 0,
          );
          availableDate = widget.availableDate;
        } else {
          final currentHour = dueHour ?? widget.dueHour;
          widget.dueDate = DateTime(
            picked.year, picked.month, picked.day,
            currentHour?.hour ?? 0, currentHour?.minute ?? 0,
          );
          dueDate = widget.dueDate;
        }
      });
    }
  }

  // ── sequence loading ──────────────────────────────────────────────────────

  Future<void> _loadSequence(int sequenceId) async {
    final bloc = context.read<NewOrderBloc>();
    setState(() {
      _loadingStations = true;
      _sequenceDetails = null;
      _machinesByType.clear();
      _selectedMachines.clear();
      _stationTimes.clear();
    });

    final sequence = await bloc.getSequenceDetails(sequenceId);
    if (!mounted) return;

    if (sequence != null) {
      final tasks = sequence.tasks ?? [];
      final uniqueTypeIds = tasks.map((task) => task.machineTypeId).toSet();
      final Map<int, MachineStandardTimes> initialTimes = {};

      for (final task in tasks) {
        final current = bloc.getStandardTimesForType(task.machineTypeId);
        final processingTime =
            current.processing != MachineStandardTimes.defaults().processing
                ? current.processing
                : task.processingUnits;
        final updated = current.copyWith(processing: processingTime);
        initialTimes[task.machineTypeId] = updated;
      }
      initialTimes.forEach((key, value) {
        bloc.updateStandardTimesForType(key, value);
      });

      if (uniqueTypeIds.isNotEmpty) {
        final futures = uniqueTypeIds
            .map((id) async =>
                dartz.Tuple2(id, await bloc.getMachinesForType(id)))
            .toList();
        final results = await Future.wait(futures);
        if (!mounted) return;

        final Map<int, List<MachineEntity>> machinesMap = {};
        for (final entry in results) {
          final times = initialTimes[entry.value1];
          machinesMap[entry.value1] = times != null
              ? entry.value2
                  .map((m) => _applyStandardTimes(m, times))
                  .toList()
              : entry.value2;
        }

        setState(() {
          _sequenceDetails = sequence;
          _machinesByType.addAll(machinesMap);
          _stationTimes.addAll(initialTimes);
          _loadingStations = false;

          for (final task in tasks) {
            final machineTypeId = task.machineTypeId;
            final machines = machinesMap[machineTypeId];
            if (machines != null && machines.isNotEmpty) {
              final machine = machines.first;
              _selectedMachines[machineTypeId] = machine;

              final processingMinutes =
                  (60 * machine.processingPercentage / 100).round();
              final preparationMinutes =
                  (60 * machine.preparationPercentage / 100).round();
              final restMinutes =
                  (60 * machine.restPercentage / 100).round();

              _explicitTaskMachineMinutes.putIfAbsent(task.id!, () => {});
              _explicitTaskMachineMinutes[task.id!]![machine.id!] = {
                'processing': processingMinutes,
                'preparation': preparationMinutes,
                'rest': restMinutes,
              };
            }
          }
        });
      } else {
        setState(() {
          _sequenceDetails = sequence;
          _stationTimes.addAll(initialTimes);
          _loadingStations = false;
        });
      }
    } else {
      setState(() => _loadingStations = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      shadowColor: Colors.black.withOpacity(0.8),
      elevation: 8,
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () =>
                    BlocProvider.of<NewOrderBloc>(context).removeJob(widget.index),
                icon: Icon(Icons.delete, color: colorScheme.error),
              ),
            ),
            TextFormField(
              controller: widget.idController,
              decoration: InputDecoration(
                labelText: 'ID del trabajo:',
                labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: widget.quantityController,
              decoration: InputDecoration(
                labelText: 'Cantidad',
                labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: widget.priorityController,
              decoration: InputDecoration(
                labelText: 'Prioridad',
                labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: selectDate('Seleccione fecha de disponibilidad',
                      availableDate, availableHour),
                ),
                const Expanded(flex: 2, child: SizedBox()),
                Expanded(
                  flex: 3,
                  child: selectDate(
                      'Seleccione fecha de entrega', dueDate, dueHour),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButton<int>(
              value: selectedSequenceValue,
              hint: Text('Seleccionar ruta de proceso',
                  style: TextStyle(color: colorScheme.onSurfaceVariant)),
              onChanged: (int? newValue) {
                if (newValue == null) return;
                setState(() {
                  selectedSequenceValue = newValue;
                  widget.selectedSequence = newValue;
                });
                _loadSequence(newValue);
              },
              items: widget.sequences
                  .map((sequence) => DropdownMenuItem<int>(
                        value: sequence.value1,
                        child: Text(sequence.value2,
                            style: TextStyle(color: colorScheme.onSurface)),
                      ))
                  .toList(),
              isExpanded: true,
              dropdownColor: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            if (_loadingStations)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            if (!_loadingStations &&
                (_sequenceDetails?.tasks?.isNotEmpty ?? false))
              ..._sequenceDetails!.tasks!.map(_buildStationRow),
          ],
        ),
      ),
    );
  }

  // ── date/time row widgets (unchanged) ─────────────────────────────────────

  Widget selectDate(String label, DateTime? date, TimeOfDay? hour) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        selectHour(hour, date, label),
        Text(
          date == null ? label : DateFormat('dd/MM/yyyy').format(date),
          style: TextStyle(color: colorScheme.onSurface),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.calendar_today, color: colorScheme.primary),
          onPressed: () => _selectDate(context, label),
        ),
      ],
    );
  }

  TextButton selectHour(TimeOfDay? hour, DateTime? date, String label) {
    return TextButton(
      onPressed: () async {
        final timeOfDay = await showTimePicker(
          context: context,
          initialTime: hour ?? TimeOfDay.now(),
        );
        if (timeOfDay != null) {
          setState(() {
            if (label == 'Seleccione fecha de disponibilidad') {
              availableHour = timeOfDay;
              widget.availableHour = timeOfDay;
              if (availableDate != null) {
                availableDate = DateTime(
                  availableDate!.year, availableDate!.month, availableDate!.day,
                  availableHour!.hour, availableHour!.minute,
                );
                widget.availableDate = availableDate;
              }
            } else if (label == 'Seleccione fecha de entrega') {
              dueHour = timeOfDay;
              widget.dueHour = timeOfDay;
              if (dueDate != null) {
                dueDate = DateTime(
                  dueDate!.year, dueDate!.month, dueDate!.day,
                  dueHour!.hour, dueHour!.minute,
                );
                widget.dueDate = dueDate;
              }
            }
          });
        }
      },
      child: hour == null
          ? const Text("Hora")
          : Text(
              "${hour.hour.toString().padLeft(2, '0')}:"
              "${hour.minute.toString().padLeft(2, '0')}"),
    );
  }

  // ── station row (unchanged except setup time field removed) ───────────────

  Widget _buildStationRow(TaskEntity task) {
    final machineTypeId = task.machineTypeId;
    final machineOptions =
        _machinesByType[machineTypeId] ?? const <MachineEntity>[];
    final selectedMachine = _selectedMachines[machineTypeId];
    final defaultLabel = _stationLabel(task);

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: machineOptions.isEmpty
                      ? null
                      : () =>
                          _showMachineSelectionDialog(task, machineOptions),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 12),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      selectedMachine?.name ?? defaultLabel,
                      style: TextStyle(
                        color: machineOptions.isEmpty
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: machineOptions.isNotEmpty
                    ? () => _showStationTimeDialog(task, machineTypeId)
                    : null,
                icon: const Icon(Icons.schedule_outlined),
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Estado dejado en la máquina: '),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _machineFinalStates[machineTypeId],
                hint: const Text("Seleccionar (A-J)"),
                items: _letters.map((String letter) {
                  return DropdownMenuItem<String>(
                    value: letter,
                    child: Text(letter),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _machineFinalStates[machineTypeId] = newValue!;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _stationLabel(TaskEntity task) {
    final name = task.machineName?.trim();
    if (name == null || name.isEmpty) return 'Estación de trabajo';
    final normalized = name.toLowerCase();
    return normalized.startsWith('estación') ? name : 'Estación de $normalized';
  }

  // ── machine selection dialog (unchanged) ──────────────────────────────────

  Future<void> _showMachineSelectionDialog(
      TaskEntity task, List<MachineEntity> options) async {
    final selected = await showDialog<MachineEntity>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            'Selecciona máquina para ${task.machineName ?? 'la estación'}'),
        content: SizedBox(
          width: double.maxFinite,
          child: options.isEmpty
              ? const Text(
                  'No hay máquinas registradas para esta estación.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final machine = options[index];
                    return ListTile(
                      title: Text(machine.name),
                      subtitle: Text(
                          'Porcentaje: '
                          '${machine.processingPercentage.toStringAsFixed(0)}%'),
                      onTap: () =>
                          Navigator.of(dialogContext).pop(machine),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (!mounted || selected == null) return;

    final bloc = context.read<NewOrderBloc>();
    setState(() {
      _selectedMachines[task.machineTypeId] = selected;
      final fallback = _stationTimes[task.machineTypeId];
      final updated =
          MachineStandardTimes.fromMachine(selected, fallback: fallback);
      _stationTimes[task.machineTypeId] = updated;
      bloc.updateStandardTimesForType(task.machineTypeId, updated);
      _syncStandardTimesToMachines(task.machineTypeId, updated);
    });
  }

  // ── station time dialog — SETUP TIME FIELD REMOVED ────────────────────────
  //
  // The "Tiempo de Alistamiento" TextField has been removed from this dialog.
  // Changeover costs are now entered exclusively in the setup-time matrix
  // (Definir matriz de tiempos de alistamiento button on the main page).
  // The 'preparation' key is still written as 0 so no downstream code breaks.

  Future<void> _showStationTimeDialog(
      TaskEntity task, int machineTypeId) async {
    final bloc = context.read<NewOrderBloc>();
    final machines = _machinesByType[machineTypeId] ?? [];

    final existingForTask = _explicitTaskMachineMinutes[task.id];
    Map<String, int>? existingTimes;
    int? existingMachineId;
    if (existingForTask != null && existingForTask.isNotEmpty) {
      existingMachineId = existingForTask.keys.first;
      existingTimes = existingForTask[existingMachineId];
    }

    int? selectedMachineId =
        existingMachineId ?? (machines.isNotEmpty ? machines[0].id : null);

    final stationDefaults = _stationTimes[machineTypeId] ??
        bloc.getStandardTimesForType(machineTypeId);

    Duration processingDuration = existingTimes != null
        ? Duration(minutes: existingTimes['processing'] ?? 0)
        : stationDefaults.processing;

    // Rest time — still configurable here.
    Duration restDuration = existingTimes != null
        ? Duration(minutes: existingTimes['rest'] ?? 0)
        : stationDefaults.rest ?? Duration.zero;

    final processingController =
        TextEditingController(text: _formatDuration(processingDuration));
    final restController =
        TextEditingController(text: _formatDuration(restDuration));

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Tiempos para ${task.machineName ?? 'Estación'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── machine selector ──────────────────────────────────────
                if (machines.isNotEmpty)
                  DropdownButton<int>(
                    value: selectedMachineId,
                    isExpanded: true,
                    items: machines
                        .map((m) => DropdownMenuItem<int>(
                            value: m.id, child: Text(m.name)))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedMachineId = v),
                  ),
                const SizedBox(height: 16),

                // ── processing time ───────────────────────────────────────
                const Text('Tiempo de Procesamiento:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextField(
                  controller: processingController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: 'HH:MM:SS',
                      border: OutlineInputBorder()),
                  inputFormatters: [_HhMmSsTextInputFormatter()],
                ),
                const SizedBox(height: 16),

                // ── rest time ─────────────────────────────────────────────
                const Text('Tiempo de Descanso:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextField(
                  controller: restController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: 'HH:MM:SS',
                      border: OutlineInputBorder()),
                  inputFormatters: [_HhMmSsTextInputFormatter()],
                ),

                // ── info note ─────────────────────────────────────────────
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.blue),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'El tiempo de alistamiento entre tipos de '
                          'job se configura en la matriz de tiempos '
                          'de alistamiento.',
                          style: TextStyle(
                              fontSize: 11, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final processingMinutes =
          _parseTimeToMinutes(processingController.text);
      final restMinutes = _parseTimeToMinutes(restController.text);

      setState(() {
        if (selectedMachineId != null) {
          _explicitTaskMachineMinutes.putIfAbsent(task.id!, () => {});
          _explicitTaskMachineMinutes[task.id!]![selectedMachineId!] = {
            'processing': processingMinutes,
            'preparation': 0, // comes from matrix — always 0 here
            'rest': restMinutes,
          };
        }
        _stationTimes[machineTypeId] = MachineStandardTimes(
          processing: Duration(minutes: processingMinutes),
          preparation: Duration.zero, // from matrix
          rest: Duration(minutes: restMinutes),
        );
      });
      bloc.updateStandardTimesForType(
          machineTypeId, _stationTimes[machineTypeId]!);
      _syncStandardTimesToMachines(
          machineTypeId, _stationTimes[machineTypeId]!);
    }
  }

  // ── helpers (unchanged) ───────────────────────────────────────────────────

  int _parseTimeToMinutes(String text) {
    final parts = text.trim().split(':');
    int h = 0, m = 0, s = 0;
    if (parts.length == 3) {
      h = int.tryParse(parts[0]) ?? 0;
      m = int.tryParse(parts[1]) ?? 0;
      s = int.tryParse(parts[2]) ?? 0;
    }
    return h * 60 + m + (s >= 30 ? 1 : 0);
  }

  MachineEntity _applyStandardTimes(
          MachineEntity machine, MachineStandardTimes times) =>
      machine;

  void _syncStandardTimesToMachines(
      int machineTypeId, MachineStandardTimes times) {
    final machines = _machinesByType[machineTypeId];
    if (machines == null) return;
    setState(() {
      _machinesByType[machineTypeId] =
          machines.map((m) => _applyStandardTimes(m, times)).toList();
      final selected = _selectedMachines[machineTypeId];
      if (selected != null) {
        _selectedMachines[machineTypeId] =
            _applyStandardTimes(selected, times);
      }
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ignore: unused_element
  List<Widget> _buildPreemptionMatrixForTask(int machineTypeId) {
    final machines = _machinesByType[machineTypeId] ?? [];
    if (machines.isEmpty) return [];
    return machines.map((machine) {
      final currentValue = _preemptionMatrix[machine.id] ?? 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Expanded(
                child:
                    Text(machine.name, style: const TextStyle(fontSize: 14))),
            ToggleButtons(
              isSelected: [currentValue == 0, currentValue == 1],
              onPressed: (index) =>
                  setState(() => _preemptionMatrix[machine.id!] = index),
              borderRadius: BorderRadius.circular(8),
              constraints:
                  const BoxConstraints(minWidth: 50, minHeight: 36),
              children: const [
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('0')),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('1')),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }
}

/// Formatter: digits only → auto-inserts colons as HH:MM:SS
class _HhMmSsTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 6) digits = digits.substring(0, 6);
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 1 || i == 3) buffer.write(':');
    }
    final text = buffer.toString();
    return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length));
  }
}