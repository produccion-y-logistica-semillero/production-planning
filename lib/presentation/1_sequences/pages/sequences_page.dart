import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:production_planning/entities/route_draft.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_state.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_state.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/graph_editor.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/machines_list.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/orders_list.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/sequence_editor_panel.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

/// Process routes: browse (read-only), create, edit in place, duplicate,
/// rename and delete.
class SequencesPage extends StatelessWidget {
  const SequencesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SeeProcessBloc>(
      create: (_) => GetIt.instance.get<SeeProcessBloc>()..retrieveSequences(),
      child: Scaffold(
        appBar: getAppBar(),
        body: const _SequencesBody(),
      ),
    );
  }
}

class _SequencesBody extends StatefulWidget {
  const _SequencesBody();

  @override
  State<_SequencesBody> createState() => _SequencesBodyState();
}

class _SequencesBodyState extends State<_SequencesBody> {
  final TextEditingController _nameController = TextEditingController();

  /// A fresh key per draft handed to the editor, so each create/edit starts
  /// from its own route and the save reads the right canvas.
  GlobalKey<NodeEditorState> _editorKey = GlobalKey<NodeEditorState>();
  int _editorDraftVersion = -1;

  /// The read-only route shown in view mode, rebuilt only when another
  /// route (or a fresh copy of it) is loaded.
  SequenceEntity? _viewedProcess;
  RouteDraft? _viewedDraft;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _syncEditor(SequencesState state) {
    if (state.isEditing && state.draftVersion != _editorDraftVersion) {
      _editorDraftVersion = state.draftVersion;
      _editorKey = GlobalKey<NodeEditorState>();
      _nameController.text = state.draft?.name ?? '';
    }
  }

  RouteDraft? _viewDraft(SequenceEntity? process) {
    if (process == null) return null;
    if (!identical(process, _viewedProcess)) {
      _viewedProcess = process;
      _viewedDraft = RouteDraft.fromSequence(process);
    }
    return _viewedDraft;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _save(BuildContext context, SequencesState state) async {
    final bloc = context.read<SequencesBloc>();
    final seeBloc = context.read<SeeProcessBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final editor = _editorKey.currentState;
    if (editor == null) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Escribe un nombre para la ruta de proceso')));
      return;
    }
    final nodes = editor.currentNodes();
    if (nodes.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Agrega al menos una estación a la ruta')));
      return;
    }

    if (state.mode == RouteEditorMode.edit) {
      final jobs = await bloc.jobsUsingCurrentRoute();
      if (jobs > 0 && context.mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Esta ruta está en uso'),
            content: Text(
              '$jobs ${jobs == 1 ? 'trabajo' : 'trabajos'} de programas de '
              'producción guardados usan esta ruta. Los cambios se aplicarán '
              'a esos programas:\n\n'
              '• Las estaciones que se mantienen conservan los tiempos que '
              'cada programa ya tiene.\n'
              '• Las estaciones nuevas usarán el tiempo estándar hasta que '
              'lo ajustes en cada programa.\n'
              '• Las estaciones que quitaste desaparecen de esos trabajos.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Guardar cambios')),
            ],
          ),
        );
        if (ok != true) return;
      }
    }

    final result = await bloc.save(RouteDraft(
      name: name,
      nodes: nodes,
      arrows: editor.currentArrows(),
    ));
    result.fold(
      (_) => messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo guardar la ruta. Intenta de nuevo.'),
        backgroundColor: Colors.redAccent,
      )),
      (id) {
        messenger.showSnackBar(
            SnackBar(content: Text('Ruta "$name" guardada')));
        seeBloc.refreshAndSelect(id);
      },
    );
  }

  Future<void> _delete(BuildContext context, SequenceEntity route) async {
    final seeBloc = context.read<SeeProcessBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final jobs = await seeBloc.countJobsUsing(route.id!);
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar ruta?'),
        content: Text(jobs == 0
            ? '¿Seguro que quieres eliminar "${route.name}"?'
            : '"${route.name}" la usan $jobs '
                '${jobs == 1 ? 'trabajo' : 'trabajos'} de programas '
                'guardados. Si la eliminas, esos programas quedarán sin '
                'ruta. ¿Eliminarla de todos modos?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await seeBloc.deleteSequence(route.id!);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Ruta "${route.name}" eliminada'
          : 'No se pudo eliminar la ruta'),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SequencesBloc, SequencesState>(
      builder: (context, state) {
        _syncEditor(state);
        final bloc = context.read<SequencesBloc>();

        final Widget left;
        final Widget board;

        if (state.isEditing) {
          left = state.machines == null
              ? Center(
                  child: state.machinesFailed
                      ? const Text('No se pudieron cargar las estaciones')
                      : const CircularProgressIndicator())
              : MachinesList(
                  machineTypes: state.machines!,
                  onSelectMachine: (m) =>
                      _editorKey.currentState?.addStation(m),
                );
          board = RouteEditorBoard(
            isEdit: state.mode == RouteEditorMode.edit,
            saving: state.saving,
            nameController: _nameController,
            editorKey: _editorKey,
            draft: state.draft,
            onSave: () => _save(context, state),
            onCancel: bloc.cancel,
          );
        } else {
          left = RouteListPanel(onNewRoute: bloc.startNew);
          board = BlocBuilder<SeeProcessBloc, SeeProcessState>(
            builder: (context, seeState) {
              final process =
                  seeState.selectedProcess == null ? null : seeState.process;
              final draft = _viewDraft(process);
              if (process == null || draft == null) {
                return Center(
                  child: Text(
                    'Selecciona una ruta de la lista o crea una nueva.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                );
              }
              return RouteViewerBoard(
                name: process.name,
                draft: draft,
                viewKey: process,
                onEdit: () => bloc.startEdit(process),
                onDuplicate: () => bloc.startDuplicate(process),
                onDelete: () => _delete(context, process),
              );
            },
          );
        }

        // Narrow window (phone, tablet in portrait): the list / palette goes
        // on top and the canvas below, instead of a fixed 280 px side panel
        // that leaves the canvas a sliver.
        return LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: (constraints.maxHeight * 0.38).clamp(220.0, 360.0),
                    child: left,
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: board),
                ],
              ),
            );
          }
          return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  IconButton(
                    tooltip: 'Qué es una ruta de proceso',
                    onPressed: () => printInfo(
                      context,
                      title: 'Ruta de proceso',
                      content:
                          'Una ruta de proceso es la secuencia de estaciones por '
                          'las que pasa un producto. Cada estación es una tarea '
                          'con un tiempo estándar, y las flechas indican qué '
                          'tarea debe terminar antes de empezar otra. Por '
                          'ejemplo, la producción de pan:\n\n'
                          'Mezclado (20 min) → Reposo (10 min) → División '
                          '(4 min) → Formado (15 min) → Horneado (1 h) → '
                          'Enfriado (40 min)',
                    ),
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
              SizedBox(width: 280, child: left),
              const SizedBox(width: 16),
              Expanded(child: board),
            ],
          ),
        );
        });
      },
    );
  }
}
