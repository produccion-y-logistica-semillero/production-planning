import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/route_draft.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/entities/task_entity.dart';


abstract class SequencesRepository{

  Future<Either<Failure, bool>> createSequence(SequenceEntity sequence);
  Future<Either<Failure, List<SequenceEntity>>> getBasicSequences();
  Future<Either<Failure, SequenceEntity?>> getFullSequence(int id);
  Future<Either<Failure, bool>> deleteSequence(int id);
  Future<int> createSequenceAndReturnId(SequenceEntity sequence);
  Future<void> createTaskForSequence(TaskEntity task, int sequenceId);
  Future<void> createTaskDependencyForSequence(TaskDependencyEntity dep);

  Future<int> createTaskForSequenceAndReturnId(TaskEntity taskEntity, int sequenceId);

  /// Creates the route (no [RouteDraft.sequenceId]) or saves it over the
  /// existing one, in a single transaction. Returns the route's id.
  ///
  /// Editing keeps the task id of every station that stays, so the times
  /// saved production programs hold for it are kept; stations removed are
  /// deleted with their arrows and per-job times.
  Future<Either<Failure, int>> saveSequenceGraph(RouteDraft draft);

  /// How many jobs of saved production programs use the route.
  Future<Either<Failure, int>> countJobsUsing(int sequenceId);

  //Future<int> createTaskForSequenceAndReturnId(TaskEntity taskEntity, int sequenceId);
}

