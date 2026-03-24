import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/setup_time_dao.dart';
import 'package:production_planning/entities/setup_time_entity.dart';
import 'package:sqflite/sqflite.dart';

class SetupTimeDaoSqllite implements SetupTimeDao {
  final Database db;

  SetupTimeDaoSqllite(this.db);

  @override
  Future<Either<Failure, int>> insert(SetupTimeEntity setupTime) async {
    try {
      final id = await db.insert('setup_times', setupTime.toMap());
      return Right(id);
    } catch (e) {
      return Left(LocalStorageFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> update(SetupTimeEntity setupTime) async {
    try {
      await db.update(
        'setup_times',
        setupTime.toMap(),
        where: 'id = ?',
        whereArgs: [setupTime.id],
      );
      return const Right(true);
    } catch (e) {
      return Left(LocalStorageFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> delete(int id) async {
    try {
      await db.delete(
        'setup_times',
        where: 'id = ?',
        whereArgs: [id],
      );
      return const Right(true);
    } catch (e) {
      return Left(LocalStorageFailure());
    }
  }

  @override
  Future<Either<Failure, List<SetupTimeEntity>>> getAllByMachine(
      int machineId) async {
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'setup_times',
        where: 'machine_id = ?',
        whereArgs: [machineId],
      );
      return Right(maps.map((map) => SetupTimeEntity.fromMap(map)).toList());
    } catch (e) {
      return Left(LocalStorageFailure());
    }
  }

  @override
  Future<Either<Failure, SetupTimeEntity?>> getSetupTime(
    int machineId,
    int? fromSequenceId,
    int toSequenceId,
  ) async {
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'setup_times',
        where:
            'machine_id = ? AND from_sequence_id ${fromSequenceId == null ? 'IS NULL' : '= ?'} AND to_sequence_id = ?',
        whereArgs: fromSequenceId == null
            ? [machineId, toSequenceId]
            : [machineId, fromSequenceId, toSequenceId],
        limit: 1,
      );

      if (maps.isEmpty) return const Right(null);
      return Right(SetupTimeEntity.fromMap(maps.first));
    } catch (e) {
      return Left(LocalStorageFailure());
    }
  }

  @override
  Future<Either<Failure, List<SetupTimeEntity>>> getAll() async {
    try {
      final List<Map<String, dynamic>> maps = await db.query('setup_times');
      return Right(maps.map((map) => SetupTimeEntity.fromMap(map)).toList());
    } catch (e) {
      return Left(LocalStorageFailure());
    }
  }
}
