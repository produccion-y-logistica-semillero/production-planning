import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/entities/route_draft.dart';

/// What the process-route screen is doing.
enum RouteEditorMode {
  /// Browsing saved routes; the canvas is read-only.
  view,

  /// Building a new route (also a duplicate of an existing one).
  create,

  /// Changing a saved route in place.
  edit,
}

class SequencesState {
  final RouteEditorMode mode;

  /// Stations (machine types) offered in the palette; null while loading.
  final List<MachineTypeEntity>? machines;
  final bool machinesFailed;

  /// The route loaded into the editor when entering create/edit mode.
  final RouteDraft? draft;

  /// Bumped every time a new draft is handed to the editor, so the page
  /// knows to (re)load the canvas exactly once per draft.
  final int draftVersion;

  final bool saving;

  const SequencesState({
    this.mode = RouteEditorMode.view,
    this.machines,
    this.machinesFailed = false,
    this.draft,
    this.draftVersion = 0,
    this.saving = false,
  });

  bool get isEditing => mode != RouteEditorMode.view;

  SequencesState copyWith({
    RouteEditorMode? mode,
    List<MachineTypeEntity>? machines,
    bool? machinesFailed,
    RouteDraft? draft,
    bool clearDraft = false,
    int? draftVersion,
    bool? saving,
  }) =>
      SequencesState(
        mode: mode ?? this.mode,
        machines: machines ?? this.machines,
        machinesFailed: machinesFailed ?? this.machinesFailed,
        draft: clearDraft ? null : (draft ?? this.draft),
        draftVersion: draftVersion ?? this.draftVersion,
        saving: saving ?? this.saving,
      );
}
