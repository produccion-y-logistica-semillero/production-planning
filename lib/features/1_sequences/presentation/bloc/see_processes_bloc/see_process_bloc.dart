import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/delete_sequence_use_case.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/get_sequence_use_case.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/get_sequences_use_case.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_event.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_state.dart';

class SeeProcessBloc extends Bloc<SeeProcessEvent, SeeProcessState>{
  final GetSequencesUseCase _getSequencesUseCase;
  final GetSequenceUseCase _getSequenceUseCase;
  final DeleteSequenceUseCase _deleteSequenceUseCase;

  SeeProcessBloc(
    this._getSequencesUseCase,
    this._getSequenceUseCase,
    this._deleteSequenceUseCase
  ): 
  super(SeeProcessInitialState(null, null, null)){
    on<OnRetrieveSequencesEvent>(
      (event, emit) async {
        final response = await _getSequencesUseCase();

        response.fold(
          (f)=> emit(SequencesRetrieveFailure(null, state.selectedProcess, state.process)), 
          (success)=> emit(SequencesRetrieved(success, state.selectedProcess, state.process))
        );
      }
    );
    on<OnSequenceSelected>(
      (event, emit) async {
        final response = await _getSequenceUseCase(p: event.id);
        response.fold(
          (f)=>emit(SequenceRetrieveFailure(state.sequences, state.selectedProcess, null)), 
         (success) => emit(SequenceRetrieveSuccess(state.sequences, event.id, success))
        );
      }
    );

    on<OnDeleteSequence>(
      (event, emit)async{
        final response = await _deleteSequenceUseCase(p: event.id);

        response.fold(
          (f)=>emit(SequenceDeletedFailure(state.sequences, state.selectedProcess, state.process))
          , (s)=> emit(SequenceDeletedSuccess(state.sequences, null, null)));
      }
    );
  }
  
}