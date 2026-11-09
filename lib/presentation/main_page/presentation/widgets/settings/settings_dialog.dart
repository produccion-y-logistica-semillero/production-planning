// The Configuración dialog: one place for the workspace, the work shift
// (Horario) and the time format, laid out like a desktop settings window
// (navigation on the left, the chosen section on the right).
import 'package:flutter/material.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/schedule_section.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/settings_widgets.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/time_format_section.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/workspace_section.dart';
import 'package:production_planning/shared/duration_input.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:production_planning/shared/workspace/workspace_session.dart';
import 'package:production_planning/shared/motion/motion.dart';

enum SettingsSection { workspace, schedule, timeFormat }

extension on SettingsSection {
  String get label => switch (this) {
        SettingsSection.workspace => 'Workspace',
        SettingsSection.schedule => 'Horario',
        SettingsSection.timeFormat => 'Formato de tiempos',
      };

  String get description => switch (this) {
        SettingsSection.workspace =>
          'Tus conjuntos de datos: abre otro, crea uno nuevo o llévalo a otro '
              'equipo exportándolo e importándolo.',
        SettingsSection.schedule =>
          'El turno en que trabajan las máquinas del workspace abierto.',
        SettingsSection.timeFormat =>
          'Cómo se escriben y se muestran todas las duraciones.',
      };

  IconData get icon => switch (this) {
        SettingsSection.workspace => Icons.workspaces_outline,
        SettingsSection.schedule => Icons.schedule,
        SettingsSection.timeFormat => Icons.timer_outlined,
      };
}

/// Lights each navigation entry in the guided tutorial (literal ids, so
/// tutorial_targets_exist_test can find them).
Widget _navTarget(SettingsSection s, Widget child) => switch (s) {
      SettingsSection.workspace =>
        TutorialTarget(id: 'config.nav.workspace', child: child),
      SettingsSection.schedule =>
        TutorialTarget(id: 'config.nav.horario', child: child),
      SettingsSection.timeFormat =>
        TutorialTarget(id: 'config.nav.formato', child: child),
    };

Future<void> showSettingsDialog(
  BuildContext context, {
  SettingsSection initial = SettingsSection.workspace,
}) =>
    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SettingsDialog(initial: initial),
    );

class SettingsDialog extends StatefulWidget {
  final SettingsSection initial;

  const SettingsDialog({super.key, this.initial = SettingsSection.workspace});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsSection _section = widget.initial;
  bool _dirty = false;

  /// True once the user agreed to close (so the PopScope lets it through).
  bool _leaving = false;

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Descartar los cambios?'),
        content: Text(
            'Hay cambios sin guardar en "${_section.label}". Si sigues, se '
            'pierden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Seguir editando')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Descartar')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _go(SettingsSection s) async {
    if (s == _section) return;
    if (!await _confirmDiscard()) return;
    setState(() {
      _section = s;
      _dirty = false;
    });
  }

  Future<void> _close() async {
    if (!await _confirmDiscard()) return;
    _forceClose();
  }

  void _forceClose() {
    if (!mounted) return;
    setState(() => _leaving = true);
    Navigator.of(context).pop();
  }

  void _onDirty(bool dirty) {
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  Widget _body() => switch (_section) {
        SettingsSection.workspace => WorkspaceSection(closeDialog: _forceClose),
        SettingsSection.schedule => ScheduleSection(
            onDirtyChanged: _onDirty, onSaved: () => setState(() {})),
        SettingsSection.timeFormat => TimeFormatSection(
            onDirtyChanged: _onDirty, onSaved: () => setState(() {})),
      };

  String _summary(SettingsSection s) => switch (s) {
        SettingsSection.workspace => openWorkspaceName.value,
        SettingsSection.schedule => scheduleSummary(),
        SettingsSection.timeFormat => timeFormatLabel(timeInputFormat.value),
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 48).clamp(320.0, 980.0);
    final height = (size.height - 48).clamp(360.0, 680.0);
    final compactNav = width < 760;

    return PopScope(
      canPop: _leaving || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SizedBox(
          width: width,
          height: height,
          // Own messenger: confirmations appear inside the dialog, not
          // behind its barrier.
          child: ScaffoldMessenger(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Column(
                children: [
                  _header(),
                  Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.6)),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _nav(compactNav),
                        VerticalDivider(
                            width: 1,
                            color: cs.outlineVariant.withValues(alpha: 0.6)),
                        Expanded(child: _content()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configuración',
                    style:
                        tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                Text('Workspace, horario y formato de tiempos',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: openWorkspaceName,
            builder: (context, ws, _) => Tooltip(
              message: 'Workspace abierto',
              child: Container(
                constraints: const BoxConstraints(maxWidth: 220),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.folder_open, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(ws,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelLarge),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TutorialTarget(
            id: 'config.close',
            child: IconButton(
              tooltip: 'Cerrar',
              onPressed: _close,
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav(bool compact) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: compact ? 76 : 248,
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in SettingsSection.values) ...[
            _navTarget(
              s,
              _NavItem(
                icon: s.icon,
                label: s.label,
                summary: _summary(s),
                selected: s == _section,
                compact: compact,
                onTap: () => _go(s),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _content() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.015, 0), end: Offset.zero)
              .animate(anim),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(_section),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_section.label,
                    style: tt.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_section.description,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String summary;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.summary,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final item = Material(
      color: selected ? cs.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 0 : 14, vertical: compact ? 14 : 12),
          child: compact
              ? Icon(icon, color: fg)
              : Row(
                  children: [
                    Icon(icon, color: fg, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: tt.titleSmall?.copyWith(
                                color: selected ? fg : cs.onSurface,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              )),
                          const SizedBox(height: 2),
                          Text(summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(color: fg)),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
    return compact
        ? Tooltip(message: '$label · $summary', child: item)
        : Semantics(selected: selected, button: true, child: item);
  }
}
