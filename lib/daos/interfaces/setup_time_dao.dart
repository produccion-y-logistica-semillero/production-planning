import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/setup_time_entity.dart';

abstract class SetupTimeDao {
  Future<Either<Failure, int>> insert(SetupTimeEntity setupTime);
  Future<Either<Failure, bool>> update(SetupTimeEntity setupTime);
  Future<Either<Failure, bool>> delete(int id);
  Future<Either<Failure, List<SetupTimeEntity>>> getAllByMachine(int machineId);
  Future<Either<Failure, SetupTimeEntity?>> getSetupTime(
      int machineId, int? fromSequenceId, int toSequenceId);
  Future<Either<Failure, List<SetupTimeEntity>>> getAll();
}
