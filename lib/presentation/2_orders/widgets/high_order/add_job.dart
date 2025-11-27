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

  AddJobWidget({
    super.key,
    required this.availableDate,
    required this.dueDate,
    required this.availableHour,
    required this.dueHour,
    required this.priorityController,
    required this.quantityController,
    required this.idController,
    required this.index,
    required this.sequences,
  });

  @override
  AddJobState createState() => AddJobState();
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
        // Si ya hay tiempos estándar ajustados para el tipo de máquina,
        // úsalo como base; de lo contrario, conserva el tiempo de la tarea
        // como valor por defecto para evitar perder la información original.
        final processingTime = current.processing !=
                MachineStandardTimes.defaults().processing
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
            .map((id) async => dartz.Tuple2(id, await bloc.getMachinesForType(id)))
            .toList();
        final results = await Future.wait(futures);
        if (!mounted) return;
        final Map<int, List<MachineEntity>> machinesMap = {};
        for (final entry in results) {
          final times = initialTimes[entry.value1];
          if (times != null) {
            machinesMap[entry.value1] = entry.value2
                .map((machine) => _applyStandardTimes(machine, times))
                .toList();
          } else {
            machinesMap[entry.value1] = entry.value2;
          }
        }
        setState(() {
          _sequenceDetails = sequence;
          _machinesByType.addAll(machinesMap);
          _stationTimes.addAll(initialTimes);
          _loadingStations = false;
        });
      } else {
        setState(() {
          _sequenceDetails = sequence;
          _stationTimes.addAll(initialTimes);
          _loadingStations = false;
        });
      }
    } else {
      setState(() {
        _loadingStations = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
                onPressed: () {
                  BlocProvider.of<NewOrderBloc>(context).removeJob(widget.index);
                },
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
                  child: selectDate('Seleccione fecha de disponibilidad', availableDate, availableHour),
                ),
                const Expanded(flex: 2, child: SizedBox()),
                Expanded(
                  flex: 3,
                  child: selectDate('Seleccione fecha de entrega', dueDate, dueHour),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButton<int>(
              value: selectedSequenceValue,
              hint: Text('Seleccionar ruta de proceso', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              onChanged: (int? newValue) {
                if (newValue == null) return;
                setState(() {
                  selectedSequenceValue = newValue;
                  widget.selectedSequence = newValue;
                });
                _loadSequence(newValue);
              },
              items: widget.sequences
                  .map(
                    (sequence) => DropdownMenuItem<int>(
                      value: sequence.value1,
                      child: Text(
                        sequence.value2,
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                    ),
                  )
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
            if (!_loadingStations && (_sequenceDetails?.tasks?.isNotEmpty ?? false))
              ..._sequenceDetails!.tasks!.map(_buildStationRow),
          ],
        ),
      ),
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
          onPressed: () {
            _selectDate(context, label);
          },
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
          : Text("${hour.hour.toString().padLeft(2, '0')}:${hour.minute.toString().padLeft(2, '0')}")
    );
  }

  Widget _buildStationRow(TaskEntity task) {
    final machineTypeId = task.machineTypeId;
    final machineOptions = _machinesByType[machineTypeId] ?? const <MachineEntity>[];
    final selectedMachine = _selectedMachines[machineTypeId];
    final defaultLabel = _stationLabel(task);

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: machineOptions.isEmpty
                  ? null
                  : () => _showMachineSelectionDialog(task, machineOptions),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
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
            onPressed: _stationTimes.containsKey(machineTypeId)
                ? () => _showStationTimeDialog(task, machineTypeId)
                : null,
            icon: const Icon(Icons.schedule_outlined),
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  String _stationLabel(TaskEntity task) {
    final name = task.machineName?.trim();
    if (name == null || name.isEmpty) {
      return 'Estación de trabajo';
    }
    final normalized = name.toLowerCase();
    if (normalized.startsWith('estación')) {
      return name;
    }
    return 'Estación de ${normalized}';
  }

  Future<void> _showMachineSelectionDialog(TaskEntity task, List<MachineEntity> options) async {
    final selected = await showDialog<MachineEntity>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Selecciona máquina para ${task.machineName ?? 'la estación'}'),
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
                        subtitle: Text('Tiempo estándar: ${_formatDuration(machine.processingTime)}'),
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
        );
      },
    );

    if (!mounted || selected == null) return;

    final bloc = context.read<NewOrderBloc>();
    setState(() {
      _selectedMachines[task.machineTypeId] = selected;
      final fallback = _stationTimes[task.machineTypeId];
      final updated = MachineStandardTimes.fromMachine(
        selected,
        fallback: fallback,
      );
      _stationTimes[task.machineTypeId] = updated;
      bloc.updateStandardTimesForType(task.machineTypeId, updated);
      _syncStandardTimesToMachines(task.machineTypeId, updated);
    });
  }

  Future<void> _showStationTimeDialog(TaskEntity task, int machineTypeId) async {
    final bloc = context.read<NewOrderBloc>();
    MachineStandardTimes localTimes =
        _stationTimes[machineTypeId] ?? bloc.getStandardTimesForType(machineTypeId);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> updateTime(
              Duration? Function(MachineStandardTimes) getter,
              MachineStandardTimes Function(MachineStandardTimes, Duration) updater,
            ) async {
              final current = getter(localTimes);
              final newDuration = await _pickDuration(current);
              if (newDuration != null) {
                localTimes = updater(localTimes, newDuration);
                setDialogState(() {});
                if (mounted) {
                  setState(() {
                    _stationTimes[machineTypeId] = localTimes;
                  });
                  bloc.updateStandardTimesForType(machineTypeId, localTimes);
                  _syncStandardTimesToMachines(machineTypeId, localTimes);
                }
              }
            }

            return AlertDialog(
              title: Text(task.machineName ?? 'Estación'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTimeOption(
                    title: 'El tiempo de procesamiento estándar de esta máquina para este trabajo es de:',
                    duration: localTimes.processing,
                    onPressed: () => updateTime(
                      (times) => times.processing,
                      (times, value) => times.copyWith(processing: value),
                    ),
                  ),
                  _buildTimeOption(
                    title: 'El tiempo estándar de preparación de esta máquina para este trabajo es de:',
                    duration: localTimes.preparation,
                    onPressed: () => updateTime(
                      (times) => times.preparation,
                      (times, value) => times.copyWith(preparation: value),
                    ),
                  ),
                  _buildTimeOption(
                    title: 'El tiempo estándar de descanso de esta máquina para este trabajo es de:',
                    duration: localTimes.rest,
                    onPressed: () => updateTime(
                      (times) => times.rest,
                      (times, value) => times.copyWith(rest: value),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (mounted) {
                      setState(() {
                        _stationTimes[machineTypeId] = localTimes;
                      });
                    }
                    bloc.updateStandardTimesForType(machineTypeId, localTimes);
                    _syncStandardTimesToMachines(machineTypeId, localTimes);
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  MachineEntity _applyStandardTimes(
    MachineEntity machine,
    MachineStandardTimes times,
  ) {
    machine.processingTime = times.processing;
    machine.preparationTime = times.preparation ?? machine.preparationTime;
    machine.restTime = times.rest ?? machine.restTime;
    return machine;
  }

  void _syncStandardTimesToMachines(
    int machineTypeId,
    MachineStandardTimes times,
  ) {
    final machines = _machinesByType[machineTypeId];
    if (machines == null) return;

    setState(() {
      final updatedMachines = machines
          .map((machine) => _applyStandardTimes(machine, times))
          .toList();
      _machinesByType[machineTypeId] = updatedMachines;

      final selected = _selectedMachines[machineTypeId];
      if (selected != null) {
        _selectedMachines[machineTypeId] = _applyStandardTimes(selected, times);
      }
    });
  }

  Widget _buildTimeOption({required String title, required Duration? duration, required VoidCallback onPressed}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 6),
                FilledButton.tonal(
                  onPressed: onPressed,
                  child: Text(duration == null ? 'Tiempo (HH:MM:SS)' : _formatDuration(duration)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onPressed,
            icon: const Icon(Icons.edit_outlined),
            color: colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Future<Duration?> _pickDuration(Duration? initial) async {
    final base = initial ?? Duration.zero;
    final initialHour = base.inHours.clamp(0, 23).toInt();
    final initialMinute = base.inMinutes % 60;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );
    if (time == null) return null;
    return Duration(hours: time.hour, minutes: time.minute);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
