// Dialogs used by the Workspace section: choosing a name, previewing a file
// before importing it, and the notices shown after exporting / importing.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/settings_widgets.dart';
import 'package:production_planning/shared/duration_input.dart';
import 'package:production_planning/shared/workspace/workspace_store.dart';

typedef NameValidator = Future<String?> Function(String name);

/// Asks for a workspace name, validating it as it is typed.
class NameDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String confirm;
  final String initial;
  final NameValidator validate;
  final bool showOpenToggle;

  const NameDialog({
    super.key,
    required this.title,
    required this.confirm,
    required this.initial,
    required this.validate,
    this.subtitle,
    this.showOpenToggle = false,
  });

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  String? _error;
  bool _checking = false;
  bool _open = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    if (widget.initial.isNotEmpty) _check();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<String?> _check() async {
    final seq = ++_seq;
    setState(() => _checking = true);
    final error = await widget.validate(_ctrl.text);
    if (!mounted || seq != _seq) return error;
    setState(() {
      // An empty field is not shown as an error, it just disables "Crear".
      _error = _ctrl.text.trim().isEmpty ? null : error;
      _checking = false;
    });
    return error;
  }

  Future<void> _submit() async {
    final error = await _check();
    if (error != null || !mounted) return;
    Navigator.of(context).pop((name: _ctrl.text.trim(), open: _open));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final canSubmit =
        _ctrl.text.trim().isNotEmpty && _error == null && !_checking;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null) ...[
              Text(widget.subtitle!,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: kMaxWorkspaceNameLength,
              decoration: InputDecoration(
                labelText: 'Nombre del workspace',
                hintText: 'Ej.: Planta Bogotá',
                border: const OutlineInputBorder(),
                errorText: _error,
                prefixIcon: const Icon(Icons.workspaces_outline),
              ),
              onChanged: (_) => _check(),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.showOpenToggle)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _open,
                onChanged: (v) => setState(() => _open = v ?? true),
                title: const Text('Abrirlo al crearlo'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

/// Shows what a file contains and asks how to import it. Returns the name
/// to use and whether an existing workspace of that name is replaced.
class ImportDialog extends StatefulWidget {
  final ImportPreview preview;
  final WorkspaceStore store;

  const ImportDialog({super.key, required this.preview, required this.store});

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

enum _ImportMode { replace, asNew }

class _ImportDialogState extends State<ImportDialog> {
  WorkspaceInfo? _existing;
  bool _loading = true;
  _ImportMode _mode = _ImportMode.asNew;
  final _ctrl = TextEditingController();
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final existing = await widget.store.find(widget.preview.suggestedName);
    final name = existing == null
        ? widget.preview.suggestedName
        : await widget.store.freeName(widget.preview.suggestedName);
    if (!mounted) return;
    setState(() {
      _existing = existing;
      _mode = existing == null ? _ImportMode.asNew : _ImportMode.replace;
      _ctrl.text = name;
      _loading = false;
    });
    await _check();
  }

  Future<void> _check() async {
    final seq = ++_seq;
    final error = await widget.store.validateName(_ctrl.text);
    if (!mounted || seq != _seq) return;
    setState(() => _error = error);
  }

  void _submit() {
    if (_mode == _ImportMode.replace && _existing != null) {
      Navigator.of(context).pop((name: _existing!.name, replace: true));
    } else if (_error == null && _ctrl.text.trim().isNotEmpty) {
      Navigator.of(context).pop((name: _ctrl.text.trim(), replace: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pv = widget.preview;
    final canSubmit = !_loading &&
        ((_mode == _ImportMode.replace && _existing != null) ||
            (_error == null && _ctrl.text.trim().isNotEmpty));

    Widget fact(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: Text(label,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              Expanded(child: Text(value, style: tt.bodyMedium)),
            ],
          ),
        );

    final exported = pv.exportedAt == null
        ? 'Sin datos de exportación'
        : '${formatWhen(pv.exportedAt)}'
            '${(pv.exportedFrom?.isNotEmpty ?? false) ? ' · equipo ${pv.exportedFrom}' : ''}';
    final shift = (pv.scheduleStart != null && pv.scheduleEnd != null)
        ? '${pv.scheduleStart} – ${pv.scheduleEnd}'
            '${pv.timeFormat != null ? ' · tiempos en ${timeFormatLabel(timeFormatFromStorage(pv.timeFormat))}' : ''}'
        : 'No incluido (se usará el horario actual)';

    return AlertDialog(
      icon: Icon(Icons.move_to_inbox_outlined, color: cs.primary, size: 32),
      title: const Text('Importar workspace'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pv.suggestedName,
                              style: tt.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          fact(Icons.insert_drive_file_outlined, 'Archivo',
                              p.basename(pv.sourcePath)),
                          fact(Icons.event_outlined, 'Exportado', exported),
                          fact(
                              Icons.inventory_2_outlined,
                              'Contenido',
                              '${pv.machines} máquinas · ${pv.sequences} rutas '
                                  '· ${pv.orders} programas'),
                          fact(Icons.schedule_outlined, 'Horario', shift),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_existing != null) ...[
                      SettingsNote(
                        tone: NoteTone.warning,
                        text: 'Ya tienes un workspace llamado '
                            '"${_existing!.name}"'
                            '${_existing!.isCurrent ? ' (es el que está abierto)' : ''}.',
                      ),
                      const SizedBox(height: 8),
                      RadioListTile<_ImportMode>(
                        contentPadding: EdgeInsets.zero,
                        value: _ImportMode.replace,
                        groupValue: _mode,
                        onChanged: (v) => setState(() => _mode = v!),
                        title: Text('Reemplazar "${_existing!.name}"'),
                        subtitle: const Text(
                            'Lo normal al traer de vuelta tus cambios. Los '
                            'datos actuales de ese workspace se sustituyen.'),
                      ),
                      RadioListTile<_ImportMode>(
                        contentPadding: EdgeInsets.zero,
                        value: _ImportMode.asNew,
                        groupValue: _mode,
                        onChanged: (v) => setState(() => _mode = v!),
                        title: const Text('Importar como un workspace nuevo'),
                        subtitle: const Text('Conserva los dos.'),
                      ),
                    ],
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: _mode == _ImportMode.asNew
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextField(
                                controller: _ctrl,
                                maxLength: kMaxWorkspaceNameLength,
                                decoration: InputDecoration(
                                  labelText: 'Nombre en este equipo',
                                  border: const OutlineInputBorder(),
                                  errorText: _error,
                                  prefixIcon:
                                      const Icon(Icons.workspaces_outline),
                                ),
                                onChanged: (_) => _check(),
                                onSubmitted: (_) => _submit(),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Se guarda una copia dentro de la aplicación; el archivo '
                      'que elegiste no se modifica.',
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: canSubmit ? _submit : null,
          icon: Icon(
              _mode == _ImportMode.replace ? Icons.sync : Icons.download_done,
              size: 18),
          label: Text(_mode == _ImportMode.replace ? 'Reemplazar' : 'Importar'),
        ),
      ],
    );
  }
}

/// After importing: where the official copy lives now. Pops true to open
/// the workspace right away.
class ImportDoneDialog extends StatelessWidget {
  final String name;
  final String internalPath;
  final String sourcePath;
  final bool alreadyOpen;

  const ImportDoneDialog({
    super.key,
    required this.name,
    required this.internalPath,
    required this.sourcePath,
    required this.alreadyOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      icon: Icon(Icons.check_circle, color: cs.primary, size: 36),
      title: Text('"$name" importado'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsLabel('Archivo oficial (aquí se guardan tus cambios)'),
            const SizedBox(height: 8),
            PathBox(internalPath),
            const SizedBox(height: 4),
            Wrap(spacing: 4, children: [
              TextButton.icon(
                onPressed: () => revealInFileManager(internalPath),
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: const Text('Mostrar en la carpeta'),
              ),
              TextButton.icon(
                onPressed: () => copyToClipboard(context, internalPath),
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copiar ruta'),
              ),
            ]),
            const SizedBox(height: 12),
            SettingsNote(
              text: 'El archivo que elegiste ya no se usa: lo que hagas a '
                  'partir de ahora se guarda en el archivo oficial, no en '
                  '"${p.basename(sourcePath)}". Puedes borrarlo si quieres.',
            ),
            const SizedBox(height: 10),
            Text(
              'Para llevar tus cambios a otro equipo usa "Exportar…" en '
              'Configuración › Workspace.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: alreadyOpen
          ? [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Listo'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Más tarde'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Abrir ahora'),
              ),
            ],
    );
  }
}

/// After exporting: where the file was written.
class ExportDoneDialog extends StatelessWidget {
  final String name;
  final String path;

  const ExportDoneDialog({super.key, required this.name, required this.path});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      icon: Icon(Icons.ios_share, color: cs.primary, size: 32),
      title: Text('"$name" exportado'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PathBox(path),
            const SizedBox(height: 12),
            Text(
              'Envía este archivo al otro equipo y ábrelo allá con '
              'Configuración › Workspace › "Importar desde archivo…". '
              'Incluye los datos, el horario y el formato de tiempos.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => unawaited(revealInFileManager(path)),
          icon: const Icon(Icons.folder_outlined, size: 18),
          label: const Text('Mostrar en la carpeta'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}
