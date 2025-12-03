import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_state.dart';
import 'package:production_planning/services/sequences_service.dart';

class SeeProcessBloc extends Cubit<SeeProcessState>{
  final SequencesService service;

  SeeProcessBloc(this.service): 
  super(SeeProcessInitialState(null, null, null));


  void retrieveSequences()async{
    final response = await  service.getSequences();
    response.fold(
      (f)=> emit(SequencesRetrieveFailure(null, state.selectedProcess, state.process)), 
      (success)=> emit(SequencesRetrieved(success, state.selectedProcess, state.process))
    );
  }

  void selectSequence(int id) async{
    final response = await service.getFullSequence(id);
    response.fold(
      (f)=>emit(SequenceRetrieveFailure(state.sequences, state.selectedProcess, null)), 
     (success) => emit(SequenceRetrieveSuccess(state.sequences, id, success))
    );
  }

  void deleteSequence(int id) async{
    final response = await service.deleteSequence(id);
    response.fold(
      (f)=>emit(SequenceDeletedFailure(state.sequences, state.selectedProcess, state.process)), 
      (s){ 
          state.sequences?.removeWhere((seq)=>seq.id == id);
          emit(SequenceDeletedSuccess(state.sequences, null, null));
        }
    );
  }
  
}