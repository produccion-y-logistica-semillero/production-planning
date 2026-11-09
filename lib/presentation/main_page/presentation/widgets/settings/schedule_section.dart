// "Horario" section of the Configuración dialog: the work shift of the
// open workspace. What does not fit in the shift continues the next day.
import 'package:flutter/material.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/settings_widgets.dart';
import 'package:production_planning/shared/date_time_pickers.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:production_planning/shared/workspace/workspace_session.dart';

class ScheduleSection extends StatefulWidget {
  final ValueChanged<bool> onDirtyChanged;
  final VoidCallback onSaved;

  const ScheduleSection({
    super.key,
    required this.onDirtyChanged,
    required this.onSaved,
  });

  @override
  State<ScheduleSection> createState() => _ScheduleSectionState();
}

class _ScheduleSectionState extends State<ScheduleSection> {
  late TimeOfDay _savedStart;
  late TimeOfDay _savedEnd;
  late TimeOfDay _start;
  late TimeOfDay _end;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _savedStart = _start = START_SCHEDULE;
    _savedEnd = _end = END_SCHEDULE;
  }

  bool get _dirty => _start != _savedStart || _end != _savedEnd;

  int get _minutes =>
      (_end.hour * 60 + _end.minute) - (_start.hour * 60 + _start.minute);

  bool get _valid => _minutes > 0;

  void _set(VoidCallback change) {
    final wasDirty = _dirty;
    setState(() {
      change();
      _error = null;
    });
    if (wasDirty != _dirty) widget.onDirtyChanged(_dirty);
  }

  Future<void> _pick(bool isStart) async {
    final picked = await pickTime(
      context,
      initial: isStart ? _start : _end,
      helpText: isStart ? 'Inicio del turno (HH:mm)' : 'Fin del turno (HH:mm)',
    );
    if (picked == null) return;
    _set(() => isStart ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    if (!_valid) {
      setState(() =>
          _error = 'La hora de fin debe ser posterior a la de inicio.');
      return;
    }
    setState(() => _saving = true);
    try {
      await saveSchedule(_start, _end);
      if (!mounted) return;
      setState(() {
        _savedStart = _start;
        _savedEnd = _end;
        _saving = false;
      });
      widget.onDirtyChanged(false);
      widget.onSaved();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('Horario guardado'),
        behavior: SnackBarBehavior.floating,
        width: 260,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar el horario: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final h = _minutes ~/ 60;
    final m = _minutes % 60;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TutorialTarget(
                  id: 'horario.content',
                  child: SettingsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SettingsLabel('Turno de trabajo'),
                        const SizedBox(height: 14),
                        LayoutBuilder(builder: (context, c) {
                          final narrow = c.maxWidth < 460;
                          final fields = [
                            _TimeField(
                              label: 'Inicio',
                              icon: Icons.wb_twilight_outlined,
                              time: _start,
                              onTap: () => _pick(true),
                            ),
                            _TimeField(
                              label: 'Fin',
                              icon: Icons.nights_stay_outlined,
                              time: _end,
                              onTap: () => _pick(false),
                            ),
                          ];
                          return narrow
                              ? Column(children: [
                                  fields[0],
                                  const SizedBox(height: 12),
                                  fields[1],
                                ])
                              : Row(children: [
                                  Expanded(child: fields[0]),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Icon(Icons.arrow_forward,
                                        color: cs.onSurfaceVariant),
                                  ),
                                  Expanded(child: fields[1]),
                                ]);
                        }),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(Icons.timelapse,
                                size: 18,
                                color: _valid ? cs.primary : cs.error),
                            const SizedBox(width: 8),
                            Text(
                              _valid
                                  ? 'Duración del turno: $h h'
                                      '${m > 0 ? ' $m min' : ''}'
                                  : 'El fin debe ser posterior al inicio',
                              style: tt.bodyMedium?.copyWith(
                                color: _valid ? cs.onSurface : cs.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const SettingsNote(
                  text: 'Las máquinas solo trabajan dentro de este turno: lo '
                      'que no alcanza a terminarse continúa al día '
                      'siguiente a la hora de inicio.',
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<String>(
                  valueListenable: openWorkspaceName,
                  builder: (context, ws, _) => SettingsNote(
                    icon: Icons.workspaces_outline,
                    text: 'Este horario pertenece al workspace "$ws" y viaja '
                        'con él cuando lo exportas a otro equipo.',
                  ),
                ),
              ],
            ),
          ),
        ),
        SettingsSaveBar(
          dirty: _dirty,
          saving: _saving,
          error: _error,
          onDiscard: () => _set(() {
            _start = _savedStart;
            _end = _savedEnd;
          }),
          onSave: _dirty ? _save : null,
          wrapSave: (b) => TutorialTarget(id: 'horario.save', child: b),
        ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final IconData icon;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimeField({
    required this.label,
    required this.icon,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: tt.labelMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      formatTimeOfDay(time),
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Cambiar hora',
                child: Icon(Icons.edit_outlined,
                    size: 18, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
