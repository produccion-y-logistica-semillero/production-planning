import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/delete_sequence_use_case.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/get_sequence_use_case.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/get_sequences_use_case.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_state.dart';

class SeeProcessBloc extends Cubit<SeeProcessState>{
  final GetSequencesUseCase _getSequencesUseCase;
  final GetSequenceUseCase _getSequenceUseCase;
  final DeleteSequenceUseCase _deleteSequenceUseCase;

  SeeProcessBloc(
    this._getSequencesUseCase,
    this._getSequenceUseCase,
    this._deleteSequenceUseCase
  ): 
  super(SeeProcessInitialState(null, null, null));


  void retrieveSequences()async{
    final response = await _getSequencesUseCase();
    response.fold(
      (f)=> emit(SequencesRetrieveFailure(null, state.selectedProcess, state.process)), 
      (success)=> emit(SequencesRetrieved(success, state.selectedProcess, state.process))
    );
  }

  void selectSequence(int id) async{
    final response = await _getSequenceUseCase(p: id);
    response.fold(
      (f)=>emit(SequenceRetrieveFailure(state.sequences, state.selectedProcess, null)), 
     (success) => emit(SequenceRetrieveSuccess(state.sequences, id, success))
    );
  }

  void deleteSequence(int id) async{
    final response = await _deleteSequenceUseCase(p: id);
    response.fold(
      (f)=>emit(SequenceDeletedFailure(state.sequences, state.selectedProcess, state.process)), 
      (s){ 
          state.sequences?.removeWhere((seq)=>seq.id == id);
          emit(SequenceDeletedSuccess(state.sequences, null, null));
        }
    );
  }
  
}