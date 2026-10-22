import 'package:flutter/material.dart';
import 'package:production_planning/entities/route_draft.dart';
import 'graph_editor.dart';

/// Right-hand board while creating or editing a route: name, save/cancel
/// and the editable canvas.
class RouteEditorBoard extends StatelessWidget {
  final bool isEdit;
  final bool saving;
  final TextEditingController nameController;
  final GlobalKey<NodeEditorState> editorKey;
  final RouteDraft? draft;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const RouteEditorBoard({
    super.key,
    required this.isEdit,
    required this.saving,
    required this.nameController,
    required this.editorKey,
    required this.draft,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(isEdit ? 'Editar ruta de proceso' : 'Nueva ruta de proceso',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la ruta',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: saving ? null : onCancel,
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(isEdit ? 'Guardar cambios' : 'Guardar ruta'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: NodeEditor(key: editorKey, initialDraft: draft),
        ),
      ],
    );
  }
}

/// Right-hand board while browsing: the selected route, read-only, with
/// its actions.
class RouteViewerBoard extends StatelessWidget {
  final String name;
  final RouteDraft draft;

  /// Identity of the loaded route: a new value rebuilds the canvas with it.
  final Object viewKey;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const RouteViewerBoard({
    super.key,
    required this.name,
    required this.draft,
    required this.viewKey,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
            OutlinedButton.icon(
              onPressed: onDuplicate,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Duplicar'),
            ),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              label: const Text('Eliminar'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${draft.nodes.length} estaciones · ${draft.arrows.length} '
          'precedencias',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Expanded(
          // A new viewer per route: it reads the route when it is built.
          child: NodeEditor(
            key: ObjectKey(viewKey),
            readOnly: true,
            initialDraft: draft,
          ),
        ),
      ],
    );
  }
}
