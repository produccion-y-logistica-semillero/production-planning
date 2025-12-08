import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/entities/task_entity.dart';

abstract class SequencesRepository {
  Future<Either<Failure, bool>> createSequence(SequenceEntity sequence);
  Future<Either<Failure, List<SequenceEntity>>> getBasicSequences();
  Future<Either<Failure, SequenceEntity?>> getFullSequence(int id);
  Future<Either<Failure, bool>> deleteSequence(int id);
  Future<int> createSequenceAndReturnId(SequenceEntity sequence);
  Future<void> createTaskForSequence(TaskEntity task, int sequenceId);
  Future<void> createTaskDependencyForSequence(TaskDependencyEntity dep);

  Future<int> createTaskForSequenceAndReturnId(
      TaskEntity taskEntity, int sequenceId);

  //Future<int> createTaskForSequenceAndReturnId(TaskEntity taskEntity, int sequenceId);
}
