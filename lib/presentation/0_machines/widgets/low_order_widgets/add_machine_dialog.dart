import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:intl/intl.dart';

class AddMachineDialog extends StatefulWidget {
  final String machineTypeName;
  final TextEditingController capacityController;
  final TextEditingController preparationController;
  final TextEditingController restTimeController;
  final TextEditingController continueController;
  final TextEditingController nameController;

  final TextEditingController availabilityDateTimeController; // Nuevo controlador
  final TextEditingController quantityController;

  final void Function(List<MachineInactivityEntity>) addMachineHandle;
  final bool isEditing;

  const AddMachineDialog(
    this.machineTypeName, {
    super.key,
    required this.nameController,
    required this.capacityController,
    required this.preparationController,
    required this.restTimeController,
    required this.continueController,
    required this.availabilityDateTimeController,
    required this.addMachineHandle,
    required this.quantityController,
    this.isEditing = false,
  });

  @override
  State<AddMachineDialog> createState() => _AddMachineDialogState();
}

class _AddMachineDialogState extends State<AddMachineDialog> {
  final List<MachineInactivityEntity> _scheduledInactivities = [];
  final TextEditingController _scheduledNameController = TextEditingController();
  final TextEditingController _scheduledDurationController = TextEditingController();
  TimeOfDay? _scheduledStart;
  final List<bool> _weekdaySelections = List<bool>.filled(Weekday.values.length, false);

  @override
  void dispose() {
    _scheduledNameController.dispose();
    _scheduledDurationController.dispose();
    super.dispose();
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

    final durationMinutes = int.tryParse(_scheduledDurationController.text.trim());
    if (durationMinutes == null || durationMinutes <= 0) {
      _showSnack('Ingresa una duración válida en minutos.', isError: true);
      return;
    }

    final startDuration = Duration(
      hours: _scheduledStart!.hour,
      minutes: _scheduledStart!.minute,
    );

    setState(() {
      _scheduledInactivities.add(MachineInactivityEntity(
        machineId: 0,
        name: name,
        weekdays: selectedDays,
        startTime: startDuration,
        duration: Duration(minutes: durationMinutes),
      ));
      _resetScheduledForm();
    });
  }

  void _onDeleteScheduled(MachineInactivityEntity inactivity) {
    setState(() {
      _scheduledInactivities.remove(inactivity);
    });
  }

  void _resetScheduledForm() {
    _scheduledNameController.clear();
    _scheduledDurationController.clear();
    _scheduledStart = null;
    for (int i = 0; i < _weekdaySelections.length; i++) {
      _weekdaySelections[i] = false;
    }
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

  Widget buildLabeledField({
    required String label,
    required Widget field,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          field,
        ],
      ),
    );
  }

  Widget _buildAutomaticPauseForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Tiempo de procesamiento continuo',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          'Define cada cuántos procesos la máquina debe tomar un descanso y la duración en minutos de esa pausa.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.continueController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Procesamientos continuos',
                  hintText: 'Ej. 4',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: widget.restTimeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutos de descanso',
                  hintText: 'Ej. 15',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () {
              FocusScope.of(context).unfocus();
              _showSnack('Tiempo de procesamiento continuo listo para guardarse con la máquina.');
            },
            icon: const Icon(Icons.save),
            label: const Text('Guardar tiempo de procesamiento continuo'),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduledForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Mantenimientos programados',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Configura mantenimientos que se aplicarán a esta nueva máquina.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _scheduledNameController,
          decoration: const InputDecoration(
            labelText: 'Nombre (ej. Mantenimiento)',
            border: OutlineInputBorder(),
            isDense: true,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    initialTime: _scheduledStart ?? const TimeOfDay(hour: 8, minute: 0),
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
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _onAddScheduled,
            icon: const Icon(Icons.add),
            label: const Text('Agregar Mantenimiento'),
          ),
        ),
        const SizedBox(height: 16),
        if (_scheduledInactivities.isNotEmpty)
          Column(
            children: _scheduledInactivities
                .map(
                  (inactivity) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
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
          ),
        const SizedBox(height: 16),
        const Divider(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => printInfo(
                      context,
                      title: widget.isEditing ? 'Editar maquina' : 'Agregar maquina especifica',
                      content: widget.isEditing
                          ? 'Edita la maquina ${widget.machineTypeName}.'
                          : 'Agrega una maquina especifica de ${widget.machineTypeName}. Utilice porcentajes para configurar los tiempos: 100% representa el tiempo estándar, valores mayores a 100% indican que la máquina es más lenta y valores menores a 100% indican que es más rápida.',
                    ),
                    icon: const Icon(Icons.info),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.isEditing ? 'Editar maquina de ${widget.machineTypeName}' : 'Nueva maquina de ${widget.machineTypeName}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 24),
              buildLabeledField(
                label: 'Nombre maquina',
                margin: const EdgeInsets.only(bottom: 20),
                field: TextField(
                  controller: widget.nameController,
                  decoration: InputDecoration(
                    hintText: 'Nombre',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
              ),
              buildLabeledField(
                label: 'Fecha de inicio',
                margin: const EdgeInsets.only(bottom: 20),
                field: TextField(
                  readOnly: true,
                  controller: widget.availabilityDateTimeController,
                  decoration: InputDecoration(
                    hintText: 'Selecciona fecha y hora',
                    prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime(2100),
                      initialDate: DateTime.now(),
                    );
                    if (date == null) return;

                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            timePickerTheme: TimePickerThemeData(
                              backgroundColor: const Color(0xFFF9F9F9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              hourMinuteShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              hourMinuteColor: MaterialStateColor.resolveWith(
                                (states) => states.contains(WidgetState.selected)
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              ),
                              hourMinuteTextColor: MaterialStateColor.resolveWith(
                                (states) => states.contains(WidgetState.selected)
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              hourMinuteTextStyle: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1,
                              ),
                              dialBackgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                              dialHandColor: Theme.of(context).colorScheme.primary,
                              dialTextColor: MaterialStateColor.resolveWith(
                                (states) => states.contains(WidgetState.selected)
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              dialTextStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              dayPeriodShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              dayPeriodColor: MaterialStateColor.resolveWith(
                                (states) => states.contains(WidgetState.selected)
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              ),
                              dayPeriodTextColor: MaterialStateColor.resolveWith(
                                (states) => states.contains(WidgetState.selected)
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              entryModeIconColor: Theme.of(context).colorScheme.primary,
                            ),
                            textButtonTheme: TextButtonThemeData(
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(context).colorScheme.primary,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              ),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (time == null) return;

                    final fullDateTime = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                    widget.availabilityDateTimeController.text =
                        DateFormat('yyyy-MM-dd HH:mm').format(fullDateTime);
                  },
                ),
              ),
              if (!widget.isEditing) _buildAutomaticPauseForm(),
              if (!widget.isEditing) _buildScheduledForm(),
              if (!widget.isEditing)
                buildLabeledField(
                  label: 'Cantidad de máquinas a crear',
                  margin: const EdgeInsets.only(bottom: 32),
                  field: TextField(
                    controller: widget.quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Cantidad',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(EdgeInsets.all(20)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 50),
                  TextButton(
                    onPressed: () => widget.addMachineHandle(_scheduledInactivities),
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(EdgeInsets.all(20)),
                    ),
                    child: Text(widget.isEditing ? 'Guardar' : 'Agregar'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

