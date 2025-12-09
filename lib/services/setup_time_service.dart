import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/setup_time_dao.dart';
import 'package:production_planning/entities/setup_time_entity.dart';

class SetupTimeService {
  final SetupTimeDao dao;

  SetupTimeService(this.dao);

  Future<Either<Failure, SetupTimeEntity>> addSetupTime({
    required int machineId,
    int? fromSequenceId,
    required int toSequenceId,
    required Duration setupDuration,
  }) async {
    final setupTime = SetupTimeEntity(
      machineId: machineId,
      fromSequenceId: fromSequenceId,
      toSequenceId: toSequenceId,
      setupDuration: setupDuration,
    );

    final result = await dao.insert(setupTime);
    return result.fold(
      (failure) => Left(failure),
      (id) {
        setupTime.id = id;
        return Right(setupTime);
      },
    );
  }

  Future<Either<Failure, bool>> updateSetupTime(
      SetupTimeEntity setupTime) async {
    return dao.update(setupTime);
  }

  Future<Either<Failure, bool>> deleteSetupTime(int id) async {
    return dao.delete(id);
  }

  Future<Either<Failure, List<SetupTimeEntity>>> getSetupTimesByMachine(
      int machineId) async {
    return dao.getAllByMachine(machineId);
  }

  Future<Either<Failure, Duration>> getSetupDuration({
    required int machineId,
    int? fromSequenceId,
    required int toSequenceId,
  }) async {
    final result =
        await dao.getSetupTime(machineId, fromSequenceId, toSequenceId);
    return result.fold(
      (failure) => Left(failure),
      (setupTime) {
        if (setupTime == null) {
          // Si no hay setup time específico, intentar buscar el genérico (fromSequenceId = null)
          if (fromSequenceId != null) {
            return getSetupDuration(
              machineId: machineId,
              fromSequenceId: null,
              toSequenceId: toSequenceId,
            );
          }
          return const Right(Duration.zero);
        }
        return Right(setupTime.setupDuration);
      },
    );
  }

  Future<Either<Failure, Map<int, Map<int?, Map<int, Duration>>>>>
      buildChangeoverMatrix() async {
    final result = await dao.getAll();
    return result.fold(
      (failure) => Left(failure),
      (setupTimes) {
        // Construir la matriz: machineId -> fromSequenceId -> toSequenceId -> Duration
        final Map<int, Map<int?, Map<int, Duration>>> matrix = {};

        for (final setupTime in setupTimes) {
          if (!matrix.containsKey(setupTime.machineId)) {
            matrix[setupTime.machineId] = {};
          }
          if (!matrix[setupTime.machineId]!
              .containsKey(setupTime.fromSequenceId)) {
            matrix[setupTime.machineId]![setupTime.fromSequenceId] = {};
          }
          matrix[setupTime.machineId]![setupTime.fromSequenceId]![
              setupTime.toSequenceId] = setupTime.setupDuration;
        }

        return Right(matrix);
      },
    );
  }
}
