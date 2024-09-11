import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';
import 'package:production_planning/features/1_sequences/domain/entities/task_entity.dart';
import 'package:production_planning/features/1_sequences/domain/repositories/sequences_repository.dart';
import 'package:production_planning/features/1_sequences/domain/request_models/new_task_model.dart';

class AddSequenceUseCase implements UseCase<bool, List<dynamic>>{

  late final SequencesRepository repository;

  AddSequenceUseCase(this.repository);

  @override
  Future<Either<Failure, bool>> call({required List<dynamic> p}) {
    final List<TaskEntity> tasks = (p[1] as List<NewTaskModel>)
          .map(
            (t) => 
            TaskEntity(
              execOrder: t.execOrder, 
              processingUnits: t.processingUnit, 
              description: t.description, 
              machineTypeId: t.machineTypeId)
          ).toList();
          
    final SequenceEntity seq = SequenceEntity(tasks, p[0] as String);
    return repository.createSequence(seq);
  }
}