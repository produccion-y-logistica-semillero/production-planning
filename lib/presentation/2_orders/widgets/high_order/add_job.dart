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
  final Map<String, MachineEntity?> _selectedMachines = {};
  final Map<String, MachineStandardTimes> _stationTimes = {};

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
      final Map<String, MachineStandardTimes> initialTimes = {};
      for (final entry in tasks.asMap().entries) {
        final task = entry.value;
        final stationKey = _stationKey(task, entry.key);
        final current = bloc.getStandardTimesForType(task.machineTypeId);
        // Si ya hay tiempos estándar ajustados para el tipo de máquina,
        // úsalo como base; de lo contrario, conserva el tiempo de la tarea
        // como valor por defecto para evitar perder la información original.
        final processingTime =
            current.processing != MachineStandardTimes.defaults().processing
                ? current.processing
                : task.processingUnits;

        final updated = current.copyWith(processing: processingTime);
        initialTimes[stationKey] = updated;
      }

      if (uniqueTypeIds.isNotEmpty) {
        final futures = uniqueTypeIds
            .map((id) async =>
                dartz.Tuple2(id, await bloc.getMachinesForType(id)))
            .toList();
        final results = await Future.wait(futures);
        if (!mounted) return;
        final Map<int, List<MachineEntity>> machinesMap = {};
        for (final entry in results) {
          machinesMap[entry.value1] = entry.value2;
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
                  BlocProvider.of<NewOrderBloc>(context)
                      .removeJob(widget.index);
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
            if (!_loadingStations &&
                (_sequenceDetails?.tasks?.isNotEmpty ?? false))
              ..._sequenceDetails!.tasks!
                  .asMap()
                  .entries
                  .map((entry) => _buildStationRow(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  MachineEntity _machineWithTimes(
    MachineEntity machine,
    MachineStandardTimes times,
  ) {
    return MachineEntity(
      id: machine.id,
      machineTypeId: machine.machineTypeId,
      status: machine.status,
      processingTime: times.processing,
      preparationTime: times.preparation ?? machine.preparationTime,
      restTime: times.rest ?? machine.restTime,
      name: machine.name,
      continueCapacity: machine.continueCapacity,
      availabilityDateTime: machine.availabilityDateTime,
      scheduledInactivities: machine.scheduledInactivities,
    );
  }

  void _updateSelectedMachineTimes(
    String stationKey,
    MachineStandardTimes times,
  ) {
    final selected = _selectedMachines[stationKey];
    if (selected == null) return;

    setState(() {
      _selectedMachines[stationKey] = _machineWithTimes(selected, times);
    });
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
          : Text(
              "${hour.hour.toString().padLeft(2, '0')}:${hour.minute.toString().padLeft(2, '0')}"),
    );
  }

  Widget _buildStationRow(int taskIndex, TaskEntity task) {
    final machineTypeId = task.machineTypeId;
    final stationKey = _stationKey(task, taskIndex);
    final machineOptions =
        _machinesByType[machineTypeId] ?? const <MachineEntity>[];
    final selectedMachine = _selectedMachines[stationKey];
    final defaultLabel = _stationLabel(task);

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: machineOptions.isEmpty
                  ? null
                  : () =>
                      _showMachineSelectionDialog(task, machineOptions, taskIndex: taskIndex),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  selectedMachine != null
                      ? '${task.description} · ${selectedMachine.name}'
                      : defaultLabel,
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
            onPressed: _stationTimes.containsKey(stationKey)
                ? () => _showStationTimeDialog(task, stationKey)
                : null,
            icon: const Icon(Icons.schedule_outlined),
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  String _stationLabel(TaskEntity task) {
    final process = task.description.trim();
    final name = task.machineName?.trim();
    if (name == null || name.isEmpty) {
      return process;
    }

    return '$process · $name';
  }

  Future<void> _showMachineSelectionDialog(
      TaskEntity task, List<MachineEntity> options,
      {required int taskIndex}) async {
    final stationKey = _stationKey(task, taskIndex);
    final selected = await showDialog<MachineEntity>(
      context: context,
      builder: (dialogContext) {
        final stationTimes = _stationTimes[stationKey];
        final optionsWithTimes = stationTimes == null
            ? options
            : options
                .map((machine) => _machineWithTimes(machine, stationTimes))
                .toList();
        return AlertDialog(
          title: Text(
            'Selecciona máquina para ${task.description}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: options.isEmpty
                ? const Text('No hay máquinas registradas para esta estación.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: optionsWithTimes.length,
                    itemBuilder: (context, index) {
                      final machine = optionsWithTimes[index];
                      return ListTile(
                        title: Text(machine.name),
                        subtitle: Text(
                            'Tiempo estándar: ${_formatDuration(machine.processingTime)}'),
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

    setState(() {
      final fallback = _stationTimes[stationKey];
      final updated = MachineStandardTimes.fromMachine(
        selected,
        fallback: fallback,
      );
      final merged = fallback == null
          ? updated
          : updated.copyWith(processing: fallback.processing);
      _stationTimes[stationKey] = merged;
      _selectedMachines[stationKey] = _machineWithTimes(selected, merged);
    });
  }

  Future<void> _showStationTimeDialog(TaskEntity task, String stationKey) async {
    final bloc = context.read<NewOrderBloc>();
    MachineStandardTimes localTimes = _stationTimes[stationKey] ??
        bloc.getStandardTimesForType(task.machineTypeId);
    final selectedMachine = _selectedMachines[stationKey];
    final machineLabel = (selectedMachine?.name ?? task.machineName ?? '').trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> updateTime(
              Duration? Function(MachineStandardTimes) getter,
              MachineStandardTimes Function(MachineStandardTimes, Duration)
                  updater,
            ) async {
              final current = getter(localTimes);
              final newDuration = await _pickDuration(current);
              if (newDuration != null) {
                localTimes = updater(localTimes, newDuration);
                setDialogState(() {});
                if (mounted) {
                  setState(() {
                    _stationTimes[stationKey] = localTimes;
                  });
                }
                _updateSelectedMachineTimes(stationKey, localTimes);
              }
            }

            return AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.description,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (machineLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        machineLabel,
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTimeOption(
                    title:
                        'Tiempo estándar de procesamiento para este proceso y estación:',
                    duration: localTimes.processing,
                    onPressed: () => updateTime(
                      (times) => times.processing,
                      (times, value) => times.copyWith(processing: value),
                    ),
                  ),
                  _buildTimeOption(
                    title:
                        'Tiempo estándar de preparación para este proceso y estación:',
                    duration: localTimes.preparation,
                    onPressed: () => updateTime(
                      (times) => times.preparation,
                      (times, value) => times.copyWith(preparation: value),
                    ),
                  ),
                  _buildTimeOption(
                    title:
                        'Tiempo estándar de descanso para este proceso y estación:',
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
                  onPressed: () async {
                    if (mounted) {
                      setState(() {
                        _stationTimes[stationKey] = localTimes;
                      });
                    }

                    final machineId = selectedMachine?.id;
                    if (machineId != null) {
                      await bloc.updateMachineTimes(
                        machineId: machineId,
                        machineTypeId: task.machineTypeId,
                        times: localTimes,
                      );
                    } else {
                      await bloc.updateStandardTimesForType(
                        task.machineTypeId,
                        localTimes,
                      );
                    }

                    _updateSelectedMachineTimes(stationKey, localTimes);
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

  Widget _buildTimeOption(
      {required String title,
      required Duration? duration,
      required VoidCallback onPressed}) {
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
                  child: Text(duration == null
                      ? 'Tiempo (HH:MM:SS)'
                      : _formatDuration(duration)),
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

  /// AQUÍ ES DONDE CAMBIA: ahora es un diálogo con TextField que auto-pone los :
  Future<Duration?> _pickDuration(Duration? initial) async {
    final initialText = initial != null ? _formatDuration(initial) : '';

    final controller = TextEditingController(text: initialText);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ingrese tiempo (HHMMSS)'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'HH:MM:SS'),
            inputFormatters: [
              _HhMmSsTextInputFormatter(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return null;

    // resultado viene como HH:MM:SS (gracias al formatter)
    final parts = result.split(':');
    if (parts.length != 3) return null;

    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final s = int.tryParse(parts[2]) ?? 0;

    return Duration(hours: h, minutes: m, seconds: s);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _stationKey(TaskEntity task, int index) {
    final process = task.description.replaceAll(' ', '_');
    return '${task.id ?? index}-${task.machineTypeId}-$process';
  }
}

/// Formatter para que al escribir números se formen HH:MM:SS automáticamente.
class _HhMmSsTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Solo dígitos
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 6) {
      digits = digits.substring(0, 6);
    }

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 1 || i == 3) {
        buffer.write(':');
      }
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
