// "Workspace" section of the Configuración dialog.
//
// A workspace is a complete set of data (stations, routes, programs, shift
// and time format). Here the user opens another one without restarting,
// creates, renames, duplicates and deletes them, and moves one to another
// computer: Exportar writes a .ppws file; Importar validates such a file
// and copies it into the app's own folder, which from then on holds the
// official copy (the picked file in Downloads is never written to).
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:production_planning/core/data/db/sqllite_database_provider.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/settings_widgets.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/workspace_dialogs.dart';
import 'package:production_planning/shared/duration_input.dart';
import 'package:production_planning/shared/tutorial/tutorial_workspace.dart';
import 'package:production_planning/shared/workspace/workspace_session.dart';
import 'package:production_planning/shared/workspace/workspace_store.dart';
import 'package:production_planning/shared/motion/motion.dart';

const _ppwsGroup = XTypeGroup(
  label: 'Workspace (.ppws)',
  extensions: [kWorkspaceExtension],
);

class WorkspaceSection extends StatefulWidget {
  /// Closes the Configuración dialog (e.g. before opening a workspace).
  final VoidCallback closeDialog;

  const WorkspaceSection({super.key, required this.closeDialog});

  @override
  State<WorkspaceSection> createState() => _WorkspaceSectionState();
}

class _WorkspaceSectionState extends State<WorkspaceSection> {
  WorkspaceStore? _store;
  List<WorkspaceInfo> _items = [];
  bool _loading = true;
  String? _busy;

  bool get _locked => inTutorialWorkspace || _busy != null;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final store = _store ?? await appWorkspaceStore();
    final items = await store.list();
    if (!mounted) return;
    setState(() {
      _store = store;
      _items = items;
      _loading = false;
    });
  }

  WorkspaceInfo? get _current {
    for (final w in _items) {
      if (w.isCurrent) return w;
    }
    return null;
  }

  // ── Running an operation ─────────────────────────────────────────────────

  Future<T?> _run<T>(String label, Future<T> Function() action) async {
    setState(() => _busy = label);
    try {
      return await action();
    } on WorkspaceException catch (e) {
      if (mounted) await _showError(e.message);
      return null;
    } catch (e) {
      if (mounted) await _showError('No se pudo completar la operación.\n$e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = null);
      await _reload();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      width: 360,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _showError(String message) => showAppDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(Icons.error_outline,
              color: Theme.of(c).colorScheme.error, size: 32),
          title: const Text('No se pudo completar'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(message),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('Entendido')),
          ],
        ),
      );

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _open(WorkspaceInfo w) async {
    widget.closeDialog();
    await switchWorkspace(w.name);
  }

  Future<void> _create() async {
    final store = _store!;
    final result = await showAppDialog<({String name, bool open})>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Nuevo workspace',
        subtitle: 'Un workspace guarda sus propias estaciones, rutas, '
            'programas, horario y formato de tiempos.',
        confirm: 'Crear',
        initial: '',
        validate: (n) => store.validateName(n),
        showOpenToggle: true,
      ),
    );
    if (result == null) return;
    final name = await _run('Creando…', () => store.create(result.name));
    if (name == null) return;
    if (result.open) {
      widget.closeDialog();
      await switchWorkspace(name);
    } else {
      _toast('Workspace "$name" creado');
    }
  }

  Future<void> _rename(WorkspaceInfo w) async {
    final store = _store!;
    final result = await showAppDialog<({String name, bool open})>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Renombrar workspace',
        confirm: 'Renombrar',
        initial: w.name,
        validate: (n) => store.validateName(n, ignoring: w.name),
      ),
    );
    if (result == null || result.name == w.name) return;
    await _run('Renombrando…', () async {
      if (w.isCurrent) {
        await withOpenWorkspaceClosed(
            () => store.rename(w.name, result.name),
            reopenAs: result.name);
      } else {
        await store.rename(w.name, result.name);
      }
    });
  }

  Future<void> _duplicate(WorkspaceInfo w) async {
    final store = _store!;
    final suggested = await store.freeName('${w.name} (copia)');
    if (!mounted) return;
    final result = await showAppDialog<({String name, bool open})>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Duplicar "${w.name}"',
        subtitle: 'Se crea una copia independiente con todos sus datos.',
        confirm: 'Duplicar',
        initial: suggested,
        validate: (n) => store.validateName(n),
      ),
    );
    if (result == null) return;
    final name = await _run(
        'Duplicando…',
        () => store.duplicate(w.name, result.name,
            openDb: w.isCurrent ? SQLLiteDatabaseProvider.current : null));
    if (name != null) _toast('Copia "$name" creada');
  }

  Future<void> _delete(WorkspaceInfo w) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (c) {
        final cs = Theme.of(c).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.delete_outline, color: cs.error, size: 32),
          title: Text('¿Eliminar "${w.name}"?'),
          content: const SizedBox(
            width: 420,
            child: Text(
                'Se borran para siempre sus estaciones, rutas, programas y '
                'resultados. Si quieres conservar una copia, expórtalo antes.'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: cs.error, foregroundColor: cs.onError),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final done = await _run('Eliminando…', () async {
      await _store!.delete(w.name);
      return true;
    });
    if (done == true) _toast('Workspace "${w.name}" eliminado');
  }

  Future<String?> _initialFolder() async {
    try {
      return (await getDownloadsDirectory())?.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _export(WorkspaceInfo w) async {
    final location = await getSaveLocation(
      suggestedName: '${w.name}.$kWorkspaceExtension',
      acceptedTypeGroups: const [_ppwsGroup],
      initialDirectory: await _initialFolder(),
      confirmButtonText: 'Exportar',
    );
    if (location == null) return;
    var dest = location.path;
    if (p.extension(dest).toLowerCase() != '.$kWorkspaceExtension') {
      dest = '$dest.$kWorkspaceExtension';
    }
    final path = await _run(
        'Exportando…',
        () => _store!.exportTo(w.name, dest,
            openDb: w.isCurrent ? SQLLiteDatabaseProvider.current : null));
    if (path == null || !mounted) return;
    await showAppDialog<void>(
      context: context,
      builder: (_) => ExportDoneDialog(name: w.name, path: path),
    );
  }

  Future<void> _import() async {
    final store = _store!;
    final file = await openFile(
      acceptedTypeGroups: const [
        _ppwsGroup,
        XTypeGroup(label: 'Base de datos (.db)', extensions: ['db']),
      ],
      initialDirectory: await _initialFolder(),
      confirmButtonText: 'Importar',
    );
    if (file == null || !mounted) return;

    final preview =
        await _run('Revisando el archivo…', () => store.inspect(file.path));
    if (preview == null || !mounted) return;

    final choice = await showAppDialog<({String name, bool replace})>(
      context: context,
      builder: (_) => ImportDialog(preview: preview, store: store),
    );
    if (choice == null || !mounted) return;

    final target = await store.find(choice.name);
    final replacingOpen =
        choice.replace && target != null && target.isCurrent;
    final internal = await _run('Importando…', () async {
      if (replacingOpen) {
        return withOpenWorkspaceClosed(() =>
            store.importFrom(preview.sourcePath, choice.name, replace: true));
      }
      return store.importFrom(preview.sourcePath, choice.name,
          replace: choice.replace);
    });
    if (internal == null || !mounted) return;

    final imported = await store.find(choice.name);
    if (!mounted) return;
    final openNow = await showAppDialog<bool>(
      context: context,
      builder: (_) => ImportDoneDialog(
        name: imported?.name ?? choice.name,
        internalPath: internal,
        sourcePath: preview.sourcePath,
        alreadyOpen: imported?.isCurrent ?? false,
      ),
    );
    if (openNow == true && imported != null && !imported.isCurrent) {
      await _open(imported);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final current = _current;
    final others = _items.where((w) => !w.isCurrent).toList();

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: _busy != null
              ? LinearProgressIndicator(key: ValueKey(_busy), minHeight: 2)
              : const SizedBox(height: 2),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 2, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (inTutorialWorkspace) ...[
                  const SettingsNote(
                    tone: NoteTone.warning,
                    icon: Icons.school_outlined,
                    text: 'Estás en el espacio de prueba del tutorial. Los '
                        'workspaces se pueden gestionar al terminar o salir '
                        'del tutorial.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (current != null) _activeCard(current),
                const SizedBox(height: 28),
                // The buttons drop below the title on narrow windows.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Otros workspaces',
                            style: tt.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          others.isEmpty
                              ? 'Solo tienes el workspace activo'
                              : '${others.length} en este equipo',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _locked ? null : _import,
                          icon: const Icon(Icons.file_open_outlined, size: 18),
                          label: const Text('Importar desde archivo…'),
                        ),
                        FilledButton.icon(
                          onPressed: _locked ? null : _create,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Nuevo'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (others.isEmpty)
                  _emptyList()
                else
                  SettingsCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < others.length; i++) ...[
                          if (i > 0)
                            Divider(
                                height: 1,
                                color:
                                    cs.outlineVariant.withValues(alpha: 0.5)),
                          _row(others[i]),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 28),
                _transferGuide(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _activeCard(WorkspaceInfo w) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final badge = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.folder_open, color: cs.onPrimary),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Flexible(
            child: Text('WORKSPACE ACTIVO',
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(
                    color: cs.primary,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: Colors.green, shape: BoxShape.circle),
          ),
        ]),
        const SizedBox(height: 4),
        Text(w.name,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(
          'Modificado ${formatWhen(w.modified)}  ·  '
          '${formatBytes(w.sizeBytes)}  ·  '
          'Turno ${scheduleSummary()}  ·  '
          'Tiempos en ${timeFormatLabel(timeInputFormat.value)}',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
    final export = FilledButton.tonalIcon(
      onPressed: _locked || !w.hasFile ? null : () => _export(w),
      icon: const Icon(Icons.ios_share, size: 18),
      label: const Text('Exportar…'),
    );
    return SettingsCard(
      emphasized: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wide: everything on one line. Narrow: "Exportar" goes below.
          LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 560
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      badge,
                      const SizedBox(width: 16),
                      Expanded(child: info),
                      const SizedBox(width: 12),
                      export,
                      _menu(w),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          badge,
                          const SizedBox(width: 16),
                          Expanded(child: info),
                          _menu(w),
                        ],
                      ),
                      const SizedBox(height: 12),
                      export,
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          const SettingsLabel('Archivo oficial de este workspace'),
          const SizedBox(height: 8),
          PathBox(w.path),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: w.hasFile ? () => revealInFileManager(w.path) : null,
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: const Text('Mostrar en la carpeta'),
              ),
              TextButton.icon(
                onPressed: () => copyToClipboard(context, w.path),
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copiar ruta'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(WorkspaceInfo w) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: _locked ? null : () => _open(w),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.workspaces_outline,
                  color: cs.onSurfaceVariant, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.name,
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    w.hasFile
                        ? 'Modificado ${formatWhen(w.modified)}  ·  '
                            '${formatBytes(w.sizeBytes)}'
                        : 'Nuevo: sus datos se crean al abrirlo por primera vez',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _locked ? null : () => _open(w),
              child: const Text('Abrir'),
            ),
            _menu(w),
          ],
        ),
      ),
    );
  }

  Widget _menu(WorkspaceInfo w) {
    final cs = Theme.of(context).colorScheme;
    PopupMenuItem<String> item(String v, IconData icon, String text,
            {bool enabled = true, Color? color}) =>
        PopupMenuItem(
          value: v,
          enabled: enabled,
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(text, style: TextStyle(color: color)),
          ]),
        );
    return PopupMenuButton<String>(
      tooltip: 'Más acciones',
      enabled: !_locked,
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        switch (v) {
          case 'rename':
            _rename(w);
          case 'duplicate':
            _duplicate(w);
          case 'export':
            _export(w);
          case 'reveal':
            revealInFileManager(w.path);
          case 'delete':
            _delete(w);
        }
      },
      itemBuilder: (_) => [
        item('rename', Icons.drive_file_rename_outline, 'Renombrar'),
        item('duplicate', Icons.copy_all_outlined, 'Duplicar',
            enabled: w.hasFile),
        if (!w.isCurrent) ...[
          item('export', Icons.ios_share, 'Exportar…', enabled: w.hasFile),
          item('reveal', Icons.folder_outlined, 'Mostrar en la carpeta',
              enabled: w.hasFile),
          const PopupMenuDivider(),
          item('delete', Icons.delete_outline, 'Eliminar', color: cs.error),
        ],
      ],
    );
  }

  Widget _emptyList() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: [
          Icon(Icons.layers_outlined, size: 32, color: cs.outline),
          const SizedBox(height: 10),
          Text('No hay otros workspaces en este equipo',
              style: tt.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Crea uno nuevo o importa el archivo .ppws que te enviaron.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _transferGuide() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    Widget step(int n, String title, String text) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: cs.secondaryContainer,
              child: Text('$n',
                  style: tt.labelMedium?.copyWith(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(text,
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        );
    final steps = [
      step(1, 'Exporta', 'Pulsa "Exportar…" y guarda el archivo .ppws.'),
      step(2, 'Envíalo', 'Por correo, USB o nube. Puede quedar en Descargas.'),
      step(3, 'Importa', 'En el otro equipo: "Importar desde archivo…".'),
    ];
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.swap_horiz, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Trabajar el mismo workspace en otro equipo',
                  style:
                      tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 16),
          // Three columns when there is room, stacked otherwise.
          LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 520
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < steps.length; i++) ...[
                        if (i > 0) const SizedBox(width: 16),
                        Expanded(child: steps[i]),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      for (var i = 0; i < steps.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        steps[i],
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            'Para volver con los cambios, exporta en ese equipo e importa '
            'aquí eligiendo "Reemplazar". Viajan los datos, el horario y el '
            'formato de tiempos.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
