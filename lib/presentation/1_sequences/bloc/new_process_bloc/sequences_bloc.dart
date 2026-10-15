import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/route_draft.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_state.dart';
import 'package:production_planning/services/machines_service.dart';
import 'package:production_planning/services/sequences_service.dart';

/// Drives the process-route screen: which mode it is in (view / create /
/// edit), the stations offered in the palette, and saving.
class SequencesBloc extends Cubit<SequencesState> {
  final SequencesService seqService;
  final MachinesService machinesService;

  SequencesBloc(this.seqService, this.machinesService)
      : super(const SequencesState()) {
    retrieveSequencesMachine();
  }

  Future<void> retrieveSequencesMachine() async {
    final response = await machinesService.getMachineTypes();
    response.fold(
      (_) => emit(state.copyWith(machinesFailed: true)),
      (machines) =>
          emit(state.copyWith(machines: machines, machinesFailed: false)),
    );
  }

  /// Start a new, empty route.
  void startNew() => _open(RouteEditorMode.create, const RouteDraft(name: ''));

  /// Edit [sequence] in place.
  void startEdit(SequenceEntity sequence) =>
      _open(RouteEditorMode.edit, RouteDraft.fromSequence(sequence));

  /// Start a new route as a copy of [sequence].
  void startDuplicate(SequenceEntity sequence) => _open(
      RouteEditorMode.create, RouteDraft.fromSequence(sequence).duplicate());

  void _open(RouteEditorMode mode, RouteDraft draft) {
    emit(state.copyWith(
      mode: mode,
      draft: draft,
      draftVersion: state.draftVersion + 1,
    ));
  }

  /// Leave create/edit mode without saving.
  void cancel() =>
      emit(state.copyWith(mode: RouteEditorMode.view, clearDraft: true));

  /// How many jobs of saved programs use the route being edited (0 for a
  /// new route).
  Future<int> jobsUsingCurrentRoute() async {
    final id = state.draft?.sequenceId;
    if (state.mode != RouteEditorMode.edit || id == null) return 0;
    final response = await seqService.countJobsUsing(id);
    return response.fold((_) => 0, (n) => n);
  }

  /// Saves [draft] (create or edit, per the current mode). On success the
  /// screen goes back to view mode; the route's id comes back so the caller
  /// can select it.
  Future<Either<Failure, int>> save(RouteDraft draft) async {
    emit(state.copyWith(saving: true));
    final toSave = state.mode == RouteEditorMode.edit
        ? draft.copyWith(sequenceId: state.draft?.sequenceId)
        : RouteDraft(name: draft.name, nodes: draft.nodes, arrows: draft.arrows);
    final result = await seqService.saveRoute(toSave);
    result.fold(
      (_) => emit(state.copyWith(saving: false)),
      (_) => emit(state.copyWith(
        saving: false,
        mode: RouteEditorMode.view,
        clearDraft: true,
      )),
    );
    return result;
  }
}
