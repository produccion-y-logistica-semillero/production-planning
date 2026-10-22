import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_state.dart';
import 'package:production_planning/services/sequences_service.dart';

class SeeProcessBloc extends Cubit<SeeProcessState>{
  final SequencesService service;

  SeeProcessBloc(this.service):
  super(SeeProcessInitialState(null, null, null));


  Future<void> retrieveSequences() async {
    final response = await  service.getSequences();
    response.fold(
      (f)=> emit(SequencesRetrieveFailure(null, state.selectedProcess, state.process)),
      (success)=> emit(SequencesRetrieved(success, state.selectedProcess, state.process))
    );
  }

  Future<void> selectSequence(int id) async {
    final response = await service.getFullSequence(id);
    response.fold(
      (f)=>emit(SequenceRetrieveFailure(state.sequences, state.selectedProcess, null)),
     (success) => emit(SequenceRetrieveSuccess(state.sequences, id, success))
    );
  }

  /// Reloads the list and shows route [id] — after it was created or edited.
  Future<void> refreshAndSelect(int id) async {
    await retrieveSequences();
    await selectSequence(id);
  }

  /// How many jobs of saved production programs use route [id].
  Future<int> countJobsUsing(int id) async {
    final response = await service.countJobsUsing(id);
    return response.fold((_) => 0, (n) => n);
  }

  Future<bool> deleteSequence(int id) async {
    final response = await service.deleteSequence(id);
    return response.fold(
      (f) {
        emit(SequenceDeletedFailure(state.sequences, state.selectedProcess, state.process));
        return false;
      },
      (s) {
        final remaining = [
          for (final seq in state.sequences ?? const <SequenceEntity>[])
            if (seq.id != id) seq,
        ];
        final stillSelected = state.selectedProcess == id ? null : state.selectedProcess;
        emit(SequenceDeletedSuccess(remaining, stillSelected,
            stillSelected == null ? null : state.process));
        return true;
      },
    );
  }

}
