// "Formato de tiempos" section of the Configuración dialog: how every
// duration (processing, setup, continuous use, rest, maintenance) is typed
// and shown. Durations are still stored in whole minutes.
import 'package:flutter/material.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/settings_widgets.dart';
import 'package:production_planning/shared/duration_input.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:production_planning/shared/workspace/workspace_session.dart';

class TimeFormatSection extends StatefulWidget {
  final ValueChanged<bool> onDirtyChanged;
  final VoidCallback onSaved;

  const TimeFormatSection({
    super.key,
    required this.onDirtyChanged,
    required this.onSaved,
  });

  @override
  State<TimeFormatSection> createState() => _TimeFormatSectionState();
}

class _TimeFormatSectionState extends State<TimeFormatSection> {
  late TimeInputFormat _saved;
  late TimeInputFormat _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _saved = _selected = timeInputFormat.value;
  }

  bool get _dirty => _selected != _saved;

  void _select(TimeInputFormat f) {
    final wasDirty = _dirty;
    setState(() {
      _selected = f;
      _error = null;
    });
    if (wasDirty != _dirty) widget.onDirtyChanged(_dirty);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await saveTimeFormat(_selected);
      if (!mounted) return;
      setState(() {
        _saved = _selected;
        _saving = false;
      });
      widget.onDirtyChanged(false);
      widget.onSaved();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('Formato de tiempos guardado'),
        behavior: SnackBarBehavior.floating,
        width: 300,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TutorialTarget(
                  id: 'formato.content',
                  child: Column(
                    children: [
                      _FormatOption(
                        title: 'Todo en minutos',
                        example: '90',
                        description: 'Un número entero de minutos. Es lo más '
                            'rápido de escribir.',
                        icon: Icons.pin_outlined,
                        selected: _selected == TimeInputFormat.minutes,
                        onTap: () => _select(TimeInputFormat.minutes),
                      ),
                      const SizedBox(height: 12),
                      _FormatOption(
                        title: 'Todo en hh:mm:ss',
                        example: '01:30:00',
                        description: 'Horas, minutos y segundos. Los segundos '
                            'se redondean al minuto al guardar.',
                        icon: Icons.schedule_outlined,
                        selected: _selected == TimeInputFormat.hms,
                        onTap: () => _select(TimeInputFormat.hms),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SettingsNote(
                  text: 'Aplica a los tiempos de proceso, alistamiento, uso '
                      'continuo, descanso y mantenimientos. Cambiar el formato '
                      'no modifica los datos: siempre se guardan en minutos.',
                ),
              ],
            ),
          ),
        ),
        SettingsSaveBar(
          dirty: _dirty,
          saving: _saving,
          error: _error,
          onDiscard: () => _select(_saved),
          onSave: _dirty ? _save : null,
          wrapSave: (b) => TutorialTarget(id: 'formato.save', child: b),
        ),
      ],
    );
  }
}

class _FormatOption extends StatelessWidget {
  final String title;
  final String example;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FormatOption({
    required this.title,
    required this.example,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                width: selected ? 2 : 1,
                color: selected
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? cs.primary : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon,
                      color: selected ? cs.onPrimary : cs.onSurfaceVariant),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(description,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    example,
                    style: tt.bodyMedium?.copyWith(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const ['Courier New', 'monospace'],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? cs.primary : cs.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
