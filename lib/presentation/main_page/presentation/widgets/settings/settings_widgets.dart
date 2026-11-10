// Building blocks shared by the sections of the Configuración dialog:
// cards, notes, the save bar and small formatting helpers.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/shared/date_time_pickers.dart';

/// A bordered surface that groups related settings.
class SettingsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool emphasized;

  const SettingsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: emphasized
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: emphasized
              ? cs.primary.withValues(alpha: 0.35)
              : cs.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: child,
    );
  }
}

enum NoteTone { info, warning, success }

/// A short highlighted explanation (info, warning or success).
class SettingsNote extends StatelessWidget {
  final String text;
  final NoteTone tone;
  final IconData? icon;
  final Widget? child;

  const SettingsNote({
    super.key,
    required this.text,
    this.tone = NoteTone.info,
    this.icon,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData ic) = switch (tone) {
      NoteTone.info => (
          cs.secondaryContainer.withValues(alpha: 0.55),
          cs.onSecondaryContainer,
          Icons.info_outline
        ),
      NoteTone.warning => (
          cs.errorContainer.withValues(alpha: 0.6),
          cs.onErrorContainer,
          Icons.warning_amber_rounded
        ),
      NoteTone.success => (
          cs.tertiaryContainer.withValues(alpha: 0.6),
          cs.onTertiaryContainer,
          Icons.check_circle_outline
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? ic, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: fg, height: 1.35)),
                if (child != null) ...[const SizedBox(height: 8), child!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar of a section with pending changes: "Descartar" / "Guardar".
class SettingsSaveBar extends StatelessWidget {
  final bool dirty;
  final bool saving;
  final String? error;
  final VoidCallback onDiscard;
  final VoidCallback? onSave;
  final Widget Function(Widget button)? wrapSave;

  const SettingsSaveBar({
    super.key,
    required this.dirty,
    required this.saving,
    required this.onDiscard,
    required this.onSave,
    this.error,
    this.wrapSave,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = error != null
        ? Text(error!, style: tt.bodySmall?.copyWith(color: cs.error))
        : dirty
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: cs.primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Cambios sin guardar',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ])
            : Text('Todo guardado',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant));
    Widget save = FilledButton.icon(
      onPressed: saving ? null : onSave,
      icon: saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.check, size: 18),
      label: const Text('Guardar'),
    );
    if (wrapSave != null) save = wrapSave!(save);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          Expanded(child: status),
          TextButton(
            onPressed: dirty && !saving ? onDiscard : null,
            child: const Text('Descartar'),
          ),
          const SizedBox(width: 8),
          save,
        ],
      ),
    );
  }
}

/// Small uppercase label above a group of values.
class SettingsLabel extends StatelessWidget {
  final String text;
  const SettingsLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

// ── Formatting and shell helpers ───────────────────────────────────────────

String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// The work shift of the open workspace, e.g. "08:00 – 16:00".
String scheduleSummary() =>
    '${formatTimeOfDay(START_SCHEDULE)} – ${formatTimeOfDay(END_SCHEDULE)}';

String formatWhen(DateTime? d) =>
    d == null ? '—' : kDateTimeFormat.format(d.toLocal());

/// Shows [path] selected in the system file manager.
Future<void> revealInFileManager(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  } catch (_) {
    // Nothing else to do: the path is also shown and can be copied.
  }
}

Future<void> copyToClipboard(BuildContext context, String text,
    {String message = 'Ruta copiada'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      width: 280,
      duration: const Duration(seconds: 2),
    ));
  }
}

/// A path shown in a monospaced, selectable box.
class PathBox extends StatelessWidget {
  final String path;
  const PathBox(this.path, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        path,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'Consolas',
              fontFamilyFallback: const ['Courier New', 'monospace'],
              color: cs.onSurface,
            ),
      ),
    );
  }
}
