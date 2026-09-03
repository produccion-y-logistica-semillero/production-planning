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

import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_standard_times.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

// Helper widget for numeric input with max value validation
class _MaxValueFormatter extends TextInputFormatter {
  final int max;
  _MaxValueFormatter(this.max);
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final val = int.tryParse(newValue.text);
    if (val != null && val > max) return oldValue;
    return newValue;
  }
}

class _HhMmSsTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.isEmpty) return newValue;

    String result = '';
    for (int i = 0; i < text.length && i < 6; i++) {
      if (i == 2 || i == 4) result += ':';
      result += text[i];
    }

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

/// Helper to create numeric input fields for HH, MM, SS with max values
Widget _bottomSheetSegment(
    TextEditingController controller, String label, int max) {
  return Expanded(
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      keyboardType: TextInputType.number,
      maxLength: 2,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
        _MaxValueFormatter(max),
      ],
      textAlign: TextAlign.center,
    ),
  );
}

// ignore: must_be_immutable
class AddJobWidget extends StatefulWidget {
  DateTime? availableDate;
  DateTime? dueDate;
  TimeOfDay? availableHour;
  TimeOfDay? dueHour;
  // Optional hour overrides for "Automático" date-registration mode: the
  // date itself is always computed at save time (today / today + lead
  // time), but the user can still pin a specific hour for each. Left null
  // means "use the current time at save time".
  TimeOfDay? automaticStartHour;
  TimeOfDay? automaticDueHour;
  final TextEditingController? priorityController;
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
    required this.idController,
    required this.index,
    required this.sequences,
    this.selectedSequence,
  }) : super(key: stateKey);

  factory AddJobWidget({
    required DateTime? availableDate,
    required DateTime? dueDate,
    required TimeOfDay? availableHour,
    required TimeOfDay? dueHour,
    required TextEditingController? priorityController,
    required TextEditingController? idController,
    required int index,
    required List<dartz.Tuple2<int, String>> sequences,
    int? selectedSequence,
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
      idController: idController,
      index: index,
      sequences: sequences,
      selectedSequence: selectedSequence,
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
  TimeOfDay? automaticStartHour;
  TimeOfDay? automaticDueHour;

  SequenceEntity? _sequenceDetails;
  bool _loadingStations = false;
  final Map<int, List<MachineEntity>> _machinesByType = {};
  final Map<int, MachineEntity?> _selectedMachines = {};
  final Map<int, MachineStandardTimes> _stationTimes = {};
  final Map<int, Map<int, Map<String, int>>> _explicitTaskMachineMinutes = {};
  final Map<int, int> _preemptionMatrix = {};

  final Map<int, String> _machineFinalStates = {};
  final List<String> _letters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J'
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
    automaticStartHour = widget.automaticStartHour;
    automaticDueHour = widget.automaticDueHour;
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
            picked.year,
            picked.month,
            picked.day,
            currentHour?.hour ?? 0,
            currentHour?.minute ?? 0,
          );
          availableDate = widget.availableDate;
        } else {
          final currentHour = dueHour ?? widget.dueHour;
          widget.dueDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            currentHour?.hour ?? 0,
            currentHour?.minute ?? 0,
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
              ? entry.value2.map((m) => _applyStandardTimes(m, times)).toList()
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

              final times = initialTimes[machineTypeId];
              final baseProcessingMinutes =
                  times?.processing.inMinutes ?? task.processingUnits.inMinutes;

              final processingMinutes =
                  (baseProcessingMinutes * machine.processingPercentage / 100)
                      .round();
              const preparationMinutes = 0; // comes from matrix — always 0 here
              final restMinutes = times?.rest?.inMinutes ??
                  (60 * machine.restPercentage / 100).round();

              _explicitTaskMachineMinutes.putIfAbsent(task.id!, () => {});
              _explicitTaskMachineMinutes[task.id!]![machine.id!] = {
                'processing': processingMinutes,
                'preparation': preparationMinutes,
                'rest': restMinutes,
              };

              // Seed the per-job preemption override for EVERY candidate
              // machine of this station from the sequence's own flag. Two
              // reasons this matters:
              //   • what the toggle shows is then always what the scheduler
              //     will use — an unseeded machine silently falls back to
              //     task.allowPreemption, so a task seeded as interruptible
              //     would display "No" while behaving as "Sí";
              //   • flexible environments only read the FIRST candidate
              //     machine's entry, so leaving gaps makes the effective
              //     value depend on map ordering.
              final int seed = task.allowPreemption ? 1 : 0;
              for (final candidate in machines) {
                if (candidate.id == null) continue;
                _preemptionMatrix.putIfAbsent(candidate.id!, () => seed);
              }
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () {
                    BlocProvider.of<NewOrderBloc>(context)
                        .duplicateJob(widget.index);
                  },
                  icon: Icon(Icons.copy_all, color: colorScheme.primary),
                  tooltip: 'Duplicar job',
                ),
                IconButton(
                  onPressed: () {
                    BlocProvider.of<NewOrderBloc>(context)
                        .removeJob(widget.index);
                  },
                  icon: Icon(Icons.delete, color: colorScheme.error),
                  tooltip: 'Eliminar job',
                ),
              ],
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
            BlocBuilder<NewOrderBloc, NewOrderState>(
              builder: (context, state) {
                final isAutomatic = state is NewOrdersState &&
                    state.dateMode == DateRegistrationMode.automatic;
                if (isAutomatic) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _selectAutomaticHour(
                                'Hora de inicio',
                                automaticStartHour,
                                (picked) => setState(() {
                                  automaticStartHour = picked;
                                  widget.automaticStartHour = picked;
                                }),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _selectAutomaticHour(
                                'Hora de entrega',
                                automaticDueHour,
                                (picked) => setState(() {
                                  automaticDueHour = picked;
                                  widget.automaticDueHour = picked;
                                }),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Las fechas se calculan automáticamente al guardar '
                          'la orden. Si dejas una hora vacía, se usa la hora '
                          'actual.',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Row(
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
                );
              },
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

  /// Hour-only picker for "Automático" mode — the date is always computed
  /// at save time, so unlike [selectHour] there's no date to merge with.
  Widget _selectAutomaticHour(
      String label, TimeOfDay? hour, ValueChanged<TimeOfDay> onPicked) {
    final colorScheme = Theme.of(context).colorScheme;
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
      ],
    );
  }

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
                  availableDate!.year,
                  availableDate!.month,
                  availableDate!.day,
                  availableHour!.hour,
                  availableHour!.minute,
                );
                widget.availableDate = availableDate;
              }
            } else if (label == 'Seleccione fecha de entrega') {
              dueHour = timeOfDay;
              widget.dueHour = timeOfDay;
              if (dueDate != null) {
                dueDate = DateTime(
                  dueDate!.year,
                  dueDate!.month,
                  dueDate!.day,
                  dueHour!.hour,
                  dueHour!.minute,
                );
                widget.dueDate = dueDate;
              }
            }
          });
        }
      },
      child: hour == null
          ? const Text("Hora")
          : Text("${hour.hour.toString().padLeft(2, '0')}:"
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
                      : () => _showMachineSelectionDialog(task, machineOptions),
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
          ..._buildPreemptionMatrixForTask(task),
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
              ? const Text('No hay máquinas registradas para esta estación.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final machine = options[index];
                    return ListTile(
                      title: Text(machine.name),
                      subtitle: Text('Porcentaje: '
                          '${machine.processingPercentage.toStringAsFixed(0)}%'),
                      onTap: () => Navigator.of(dialogContext).pop(machine),
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

      // Update explicit times mapping for this task & machine
      final baseProcessingMinutes = updated.processing.inMinutes;
      final restMinutes = updated.rest?.inMinutes ??
          (60 * selected.restPercentage / 100).round();
      _explicitTaskMachineMinutes.putIfAbsent(task.id!, () => {});
      _explicitTaskMachineMinutes[task.id!]!.clear();
      _explicitTaskMachineMinutes[task.id!]![selected.id!] = {
        'processing': baseProcessingMinutes,
        'preparation': 0, // setup times come from matrix
        'rest': restMinutes,
      };

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

    // Without this, tapping into a pre-filled field (e.g. showing the
    // stale "00:05:00" default) places the cursor instead of selecting the
    // existing text — since _HhMmSsTextInputFormatter always keeps only the
    // FIRST 6 digits of the resulting string, typing a new value without
    // first clearing the field just gets truncated away and the old value
    // silently "wins", making the field look impossible to edit.
    final processingFocusNode = FocusNode();
    processingFocusNode.addListener(() {
      if (processingFocusNode.hasFocus) {
        processingController.selection = TextSelection(
            baseOffset: 0, extentOffset: processingController.text.length);
      }
    });
    final restFocusNode = FocusNode();
    restFocusNode.addListener(() {
      if (restFocusNode.hasFocus) {
        restController.selection = TextSelection(
            baseOffset: 0, extentOffset: restController.text.length);
      }
    });

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
                  focusNode: processingFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: 'HH:MM:SS', border: OutlineInputBorder()),
                  inputFormatters: [_HhMmSsTextInputFormatter()],
                ),
                const SizedBox(height: 16),

                // ── rest time ─────────────────────────────────────────────
                const Text('Tiempo de Descanso:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextField(
                  controller: restController,
                  focusNode: restFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: 'HH:MM:SS', border: OutlineInputBorder()),
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
                      Icon(Icons.info_outline, size: 16, color: Colors.blue),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'El tiempo de alistamiento entre tipos de '
                          'job se configura en la matriz de tiempos '
                          'de alistamiento.',
                          style: TextStyle(fontSize: 11, color: Colors.blue),
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
      final processingMinutes = _parseTimeToMinutes(processingController.text);
      final restMinutes = _parseTimeToMinutes(restController.text);

      setState(() {
        if (selectedMachineId != null) {
          final newSelMachine =
              machines.firstWhere((m) => m.id == selectedMachineId);
          _selectedMachines[machineTypeId] = newSelMachine;

          _explicitTaskMachineMinutes.putIfAbsent(task.id!, () => {});
          _explicitTaskMachineMinutes[task.id!]!.clear();
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

    processingFocusNode.dispose();
    restFocusNode.dispose();
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
        _selectedMachines[machineTypeId] = _applyStandardTimes(selected, times);
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

  // ── per-job preemption ────────────────────────────────────────────────────

  /// One "¿Interrumpible?" switch per candidate machine of this station.
  ///
  /// The value lands in `job_preemption` and wins over the sequence's own
  /// `allow_preemption`, so two jobs of the same order — even on the same
  /// route — can be interruptible independently. Values are seeded from the
  /// sequence when it loads, so the switch never shows something different
  /// from what the scheduler will do.
  List<Widget> _buildPreemptionMatrixForTask(TaskEntity task) {
    final machines = _machinesByType[task.machineTypeId] ?? const [];
    if (machines.isEmpty) return const [];

    final colorScheme = Theme.of(context).colorScheme;
    final widgets = <Widget>[
      const SizedBox(height: 12),
      const Text(
        '¿Se puede interrumpir en esta máquina?',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const Text(
        'Si no, el trabajo espera a que haya un bloque libre completo en vez '
        'de partirse.',
        style: TextStyle(fontSize: 11),
      ),
    ];

    for (final machine in machines) {
      if (machine.id == null) continue;
      final int currentValue =
          _preemptionMatrix[machine.id] ?? (task.allowPreemption ? 1 : 0);
      final String? warning =
          currentValue == 0 ? _uninterruptibleWarning(task, machine) : null;

      widgets.add(Padding(
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
              constraints: const BoxConstraints(minWidth: 50, minHeight: 36),
              children: const [
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('No')),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Sí')),
              ],
            ),
          ],
        ),
      ));

      if (warning != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: colorScheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning,
                  style: TextStyle(fontSize: 11, color: colorScheme.error),
                ),
              ),
            ],
          ),
        ));
      }
    }

    return widgets;
  }

  /// Explains, before the order is even saved, why marking this job as
  /// non-interruptible on [machine] cannot be honoured — the scheduler will
  /// split it anyway rather than search forever for a block that does not
  /// exist. Returns null when the choice is satisfiable.
  String? _uninterruptibleWarning(TaskEntity task, MachineEntity machine) {
    final duration = _effectiveProcessingDuration(task, machine);
    if (duration <= Duration.zero) return null;

    if (machine.continueCapacity > 0 &&
        duration.inMinutes > machine.continueCapacity) {
      return 'Dura ${_formatDuration(duration)} y la máquina descansa cada '
          '${machine.continueCapacity} min de uso continuo, así que se '
          'partirá de todos modos.';
    }

    // Same calculation the scheduler uses, so the warning cannot disagree
    // with what actually happens.
    final engine = PreemptionEngine(
      workingSchedule: dartz.Tuple2(START_SCHEDULE, END_SCHEDULE),
      maintenanceWindows: machine.scheduledInactivities,
    );
    final longest = engine.largestContiguousWindow();

    if (longest <= Duration.zero) {
      return 'La máquina no tiene ningún horario disponible: la jornada '
          'laboral está vacía o los mantenimientos la cubren por completo. '
          'La orden no se podrá planificar.';
    }
    if (duration > longest) {
      return 'Dura ${_formatDuration(duration)} y el bloque libre más largo '
          'de esta máquina es ${_formatDuration(longest)} (jornada menos '
          'mantenimientos), así que se partirá de todos modos.';
    }
    return null;
  }

  /// The processing time the scheduler will actually use for this
  /// task/machine pair, following the same precedence as the adapters:
  /// explicit time first, then the sequence's own time scaled by the
  /// machine's percentage.
  Duration _effectiveProcessingDuration(TaskEntity task, MachineEntity machine) {
    final explicit = _explicitTaskMachineMinutes[task.id]?[machine.id]
        ?['processing'];
    if (explicit != null) return Duration(minutes: explicit);

    final base = _stationTimes[task.machineTypeId]?.processing ??
        task.processingUnits;
    if (machine.processingPercentage == 100 ||
        machine.processingPercentage <= 0) {
      return base;
    }
    final ratio = machine.processingPercentage / 100.0;
    return Duration(milliseconds: (base.inMilliseconds * ratio).round());
  }
}
