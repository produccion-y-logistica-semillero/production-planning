import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/presentation/0_machines/bloc/machine_inactivities_cubit/machine_inactivities_cubit.dart';
import 'package:production_planning/presentation/0_machines/bloc/machine_inactivities_cubit/machine_inactivities_state.dart';

class MachineInactivitiesDialog extends StatefulWidget {
  final MachineEntity machine;

  const MachineInactivitiesDialog({super.key, required this.machine});

  @override
  State<MachineInactivitiesDialog> createState() =>
      _MachineInactivitiesDialogState();
}

class _MachineInactivitiesDialogState extends State<MachineInactivitiesDialog> {
  late final TextEditingController _continueCapacityController;
  late final TextEditingController _restMinutesController;
  final TextEditingController _scheduledNameController =
      TextEditingController();
  final TextEditingController _scheduledDurationController =
      TextEditingController();
  TimeOfDay? _scheduledStart;
  final List<bool> _weekdaySelections =
      List<bool>.filled(Weekday.values.length, false);
  bool _automaticInitialized = false;
  bool _scheduledCountInitialized = false;
  int _lastScheduledCount = 0;

  @override
  void initState() {
    super.initState();
    _continueCapacityController = TextEditingController();
    _restMinutesController = TextEditingController();
  }

  @override
  void dispose() {
    _continueCapacityController.dispose();
    _restMinutesController.dispose();
    _scheduledNameController.dispose();
    _scheduledDurationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MachineInactivitiesCubit, MachineInactivitiesState>(
      listener: (context, state) {
        if (!_scheduledCountInitialized && state.hasMachine) {
          _lastScheduledCount = state.scheduled.length;
          _scheduledCountInitialized = true;
        }

        if (state.successMessage != null) {
          _showSnack(state.successMessage!);
          context.read<MachineInactivitiesCubit>().clearFeedback();
        }
        if (state.errorMessage != null) {
          _showSnack(state.errorMessage!, isError: true);
          context.read<MachineInactivitiesCubit>().clearFeedback();
        }

        if (state.scheduled.length != _lastScheduledCount) {
          _resetScheduledForm();
          _lastScheduledCount = state.scheduled.length;
        }
      },
      builder: (context, state) {
        if (!_automaticInitialized && state.hasMachine) {
          _continueCapacityController.text = state.continueCapacity > 0
              ? state.continueCapacity.toString()
              : '';
          _restMinutesController.text =
              state.restTime != null && state.restTime!.inMinutes > 0
                  ? state.restTime!.inMinutes.toString()
                  : '';
          _automaticInitialized = true;
        }

        final theme = Theme.of(context);

        return Dialog(
          insetPadding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Inactividades: ${widget.machine.name}',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    _buildAutomaticSection(state, theme),
                    const SizedBox(height: 32),
                    _buildScheduledSection(state, theme),
                    const SizedBox(height: 32),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cerrar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAutomaticSection(
      MachineInactivitiesState state, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pausa automática por límite de procesamientos',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          'Define cada cuántos procesos la máquina debe tomar un descanso y la duración en minutos de esa pausa.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _continueCapacityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Procesamientos continuos',
                  hintText: 'Ej. 4',
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _restMinutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutos de descanso',
                  hintText: 'Ej. 15',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: state.isSavingAutomatic ? null : _onSaveAutomatic,
            icon: state.isSavingAutomatic
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Guardar pausa automática'),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduledSection(
      MachineInactivitiesState state, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Programaciones recurrentes',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          'Configura mantenimientos, pausas obligatorias o detenciones recurrentes.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        _buildScheduledForm(state),
        const SizedBox(height: 24),
        state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildScheduledList(state, theme),
      ],
    );
  }

  Widget _buildScheduledForm(MachineInactivitiesState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _scheduledNameController,
          decoration: const InputDecoration(
            labelText: 'Nombre (ej. Mantenimiento)',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Días de la semana',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        ToggleButtons(
          isSelected: _weekdaySelections,
          onPressed: (index) {
            setState(() {
              _weekdaySelections[index] = !_weekdaySelections[index];
            });
          },
          borderRadius: BorderRadius.circular(12),
          children: Weekday.values
              .map((day) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(day.shortLabel),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime:
                        _scheduledStart ?? const TimeOfDay(hour: 8, minute: 0),
                  );
                  if (picked != null) {
                    setState(() => _scheduledStart = picked);
                  }
                },
                icon: const Icon(Icons.access_time),
                label: Text(_scheduledStart == null
                    ? 'Hora de inicio'
                    : '${_scheduledStart!.hour.toString().padLeft(2, '0')}:${_scheduledStart!.minute.toString().padLeft(2, '0')}'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _scheduledDurationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duración (minutos)',
                  hintText: 'Ej. 30',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: state.isSavingScheduled ? null : _onAddScheduled,
            icon: state.isSavingScheduled
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: const Text('Agregar'),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduledList(MachineInactivitiesState state, ThemeData theme) {
    if (state.scheduled.isEmpty) {
      return Text(
        'No hay inactividades programadas.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      children: state.scheduled
          .map(
            (inactivity) => Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(inactivity.name),
                subtitle: Text(
                  '${_formatWeekdays(inactivity.weekdays)} • ${inactivity.formattedStartTime()} • ${inactivity.duration.inMinutes} min',
                ),
                trailing: IconButton(
                  onPressed: () => _onDeleteScheduled(inactivity),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Eliminar inactividad',
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  void _onSaveAutomatic() {
    final continueCapacity =
        int.tryParse(_continueCapacityController.text.trim());
    if (continueCapacity == null || continueCapacity <= 0) {
      _showSnack('Ingresa un número válido de procesamientos continuos.',
          isError: true);
      return;
    }

    final restMinutesText = _restMinutesController.text.trim();
    Duration? restDuration;
    if (restMinutesText.isNotEmpty) {
      final restMinutes = int.tryParse(restMinutesText);
      if (restMinutes == null || restMinutes < 0) {
        _showSnack('Ingresa una duración en minutos válida.', isError: true);
        return;
      }
      restDuration = Duration(minutes: restMinutes);
    }

    context.read<MachineInactivitiesCubit>().saveAutomatic(
          continueCapacity: continueCapacity,
          restTime: restDuration,
        );
  }

  void _onAddScheduled() {
    final name = _scheduledNameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Ingresa un nombre para la inactividad.', isError: true);
      return;
    }

    final selectedDays = <Weekday>{};
    for (int i = 0; i < _weekdaySelections.length; i++) {
      if (_weekdaySelections[i]) selectedDays.add(Weekday.values[i]);
    }
    if (selectedDays.isEmpty) {
      _showSnack('Selecciona al menos un día de la semana.', isError: true);
      return;
    }

    if (_scheduledStart == null) {
      _showSnack('Selecciona la hora de inicio.', isError: true);
      return;
    }

    final durationMinutes =
        int.tryParse(_scheduledDurationController.text.trim());
    if (durationMinutes == null || durationMinutes <= 0) {
      _showSnack('Ingresa una duración válida en minutos.', isError: true);
      return;
    }

    final startDuration = Duration(
      hours: _scheduledStart!.hour,
      minutes: _scheduledStart!.minute,
    );

    context.read<MachineInactivitiesCubit>().addScheduled(
          name: name,
          weekdays: selectedDays,
          startTime: startDuration,
          duration: Duration(minutes: durationMinutes),
        );
  }

  void _onDeleteScheduled(MachineInactivityEntity inactivity) {
    final id = inactivity.id;
    if (id == null) {
      _showSnack('No se puede eliminar este registro.', isError: true);
      return;
    }
    context.read<MachineInactivitiesCubit>().removeScheduled(id);
  }

  void _resetScheduledForm() {
    _scheduledNameController.clear();
    _scheduledDurationController.clear();
    _scheduledStart = null;
    for (int i = 0; i < _weekdaySelections.length; i++) {
      _weekdaySelections[i] = false;
    }
    setState(() {});
  }

  String _formatWeekdays(Set<Weekday> weekdays) {
    if (weekdays.length == Weekday.values.length) {
      return 'Todos los días';
    }
    return weekdays.map((day) => day.shortLabel).join(', ');
  }

  void _showSnack(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : null,
      ),
    );
  }
}
