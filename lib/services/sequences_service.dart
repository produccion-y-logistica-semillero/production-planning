import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/presentation/1_sequences/request_models/new_task_model.dart';
import 'package:production_planning/repositories/interfaces/sequences_repository.dart';

class SequencesService {
  final SequencesRepository repository;
  SequencesService(this.repository);

  Future<Either<Failure, bool>> addSequence(
      List<NewTaskModel> tasksRequest, String name) {
    final List<TaskEntity> tasks = tasksRequest
        .map((t) => TaskEntity(
            processingUnits: t.processingUnit,
            description: t.description,
            machineTypeId: t.machineTypeId,
            machineName: null,
            allowPreemption: t.allowPreemption))
        .toList();

    final SequenceEntity seq = SequenceEntity(null, tasks, name, /*--- */ null);
    return repository.createSequence(seq);
  }

  Future<Either<Failure, bool>> deleteSequence(int id) async {
    return repository.deleteSequence(id);
  }

  Future<Either<Failure, SequenceEntity?>> getFullSequence(int id) {
    return repository.getFullSequence(id);
  }

  Future<Either<Failure, List<SequenceEntity>>> getSequences() {
    return repository.getBasicSequences();
  }

  Future<Either<Failure, bool>> addSequenceWithGraph(
    List<NewTaskModel> tasks,
    List<Map<String, int>> dependencies,
    String processName,
  ) async {
    try {
      // 1. Crea la secuencia y obtén el ID
      final SequenceEntity seq = SequenceEntity(null, [], processName, null);
      final int sequenceId = await repository.createSequenceAndReturnId(seq);

      // 2. Guarda las tareas con el sequenceId y mapea machineTypeId -> taskId
      final Map<int, int> machineTypeIdToTaskId = {};
      for (final t in tasks) {
        final taskEntity = TaskEntity(
          processingUnits: t.processingUnit,
          description: t.description,
          machineTypeId: t.machineTypeId,
          machineName: t.machineName,
          allowPreemption: t.allowPreemption,
        );
        final int taskId = await repository.createTaskForSequenceAndReturnId(
            taskEntity, sequenceId);
        machineTypeIdToTaskId[t.machineTypeId] = taskId;
      }

      // 3. Guarda las dependencias con el sequenceId usando los taskId reales
      for (final d in dependencies) {
        final predTaskId = machineTypeIdToTaskId[d['predecessor_id']];
        final succTaskId = machineTypeIdToTaskId[d['successor_id']];

        if (predTaskId != null && succTaskId != null) {
          final depEntity = TaskDependencyEntity(
            predecessor_id: predTaskId,
            successor_id: succTaskId,
            sequenceId: sequenceId,
          );

          await repository.createTaskDependencyForSequence(depEntity);
        } else {}
      }

      return const Right(true);
    } catch (e) {
      return Left(LocalStorageFailure());
    }
  }
}
