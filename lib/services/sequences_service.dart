import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/presentation/1_sequences/request_models/new_task_model.dart';
import 'package:production_planning/repositories/interfaces/sequences_repository.dart';

class SequencesService {

  final SequencesRepository repository;
  SequencesService(this.repository);

  Future<Either<Failure, bool>> addSequence(List<NewTaskModel> tasksRequest, String name) {
    final List<TaskEntity> tasks = tasksRequest
          .map(
            (t) => 
            TaskEntity(
              execOrder: t.execOrder, 
              processingUnits: t.processingUnit, 
              description: t.description, 
              machineTypeId: t.machineTypeId,
              machineName: null)
          ).toList();
          
    final SequenceEntity seq = SequenceEntity(null, tasks, name);
    return repository.createSequence(seq);
  }

  Future<Either<Failure, bool>> deleteSequence(int id) async{
    return repository.deleteSequence(id);
  }

  Future<Either<Failure, SequenceEntity?>> getFullSequence(int id){
    return repository.getFullSequence(id);
  }

  Future<Either<Failure, List<SequenceEntity>>> getSequences() {
    return repository.getBasicSequences();
  }
}