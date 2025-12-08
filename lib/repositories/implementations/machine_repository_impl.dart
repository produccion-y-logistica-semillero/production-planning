import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/machine_dao.dart';
import 'package:production_planning/daos/interfaces/machine_inactivity_dao.dart';
import 'package:production_planning/daos/interfaces/machine_type_dao.dart';
import 'package:production_planning/daos/interfaces/status_dao.dart';
import 'package:production_planning/repositories/models/machine_type_model.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';

class MachineRepositoryImpl implements MachineRepository {
  final MachineTypeDao machineTypeDao;
  final MachineDao machineDao;
  final StatusDao statusDao;
  final MachineInactivityDao machineInactivityDao;

  MachineRepositoryImpl({
    required this.machineTypeDao,
    required this.machineDao,
    required this.statusDao,
    required this.machineInactivityDao,
  });

  @override
  Future<Either<Failure, List<MachineTypeEntity>>> getAllMachineTypes() async {
    try {
      return Right((await machineTypeDao.getAllMachines())
          .map((model) => model.toEntity())
          .toList());
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  //need to check if it's good to get only the ID or if it could be better to get the entire entry
  @override
  Future<Either<Failure, int>> insertMachineType(
      MachineTypeEntity machine) async {
    try {
      int id = await machineTypeDao
          .insertMachine(MachineTypeModel.fromEntity(machine));
      return Right(id);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, bool>> deleteMachineType(int id) async {
    try {
      await machineDao.deleteWhere(machineTypeDao.getTablePK(),
          id); //we delete first all the machines associated with that machine type
      bool res = await machineTypeDao.deleteMachine(id);
      return Right(res);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, List<MachineEntity>>> getAllMachinesFromType(
      int machineTypeId) async {
    try {
      final machines = (await machineDao.getMachinesByType(machineTypeId))
          .map((map) async => await jsonToEntity(map))
          .toList();
      List<MachineEntity> machinesReady = [];
      for (final mach in machines) {
        final future = await mach;
        machinesReady.add(future);
      }
      return Right(machinesReady);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  //Machines Specific Implementations

  @override
  Future<Either<Failure, bool>> deleteMachine(int id) async {
    try {
      bool res = await machineDao.delete(id);
      return Right(res);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, int>> insertMachine(MachineEntity machine) async {
    try {
      int id =
          await machineDao.insertMachine(await machineEntityToJson(machine));
      return Right(id);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, int>> countMachinesOf(int machineTypeId) async {
    try {
      int amount = await machineDao.getMachinesCount(machineTypeId);
      return Right(amount);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, String>> getMachineTypeName(int machineTypeId) async {
    try {
      String name = await machineTypeDao.getMachineName(machineTypeId);
      return Right(name);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  Future<Map<String, dynamic>> machineEntityToJson(MachineEntity entity) async {
    return {
      "machine_type_id": entity.machineTypeId,
      "machine_name": entity.name,
      "status_id": entity.status != null
          ? await statusDao.getIdByName(entity.status)
          : await statusDao.getDefaultStatusId(),
      "processing_percentage": entity.processingPercentage,
      "preparation_percentage": entity.preparationPercentage,
      "rest_percentage": entity.restPercentage,
      "continue_capacity": entity.continueCapacity,
      "availability_time": entity.availabilityDateTime.toString()
    };
  }

  Future<MachineEntity> jsonToEntity(Map<String, dynamic> map) async {
    final scheduled = await _getMachineInactivities(map["machine_id"]);
    return MachineEntity(
      id: map["machine_id"],
      machineTypeId: map["machine_type_id"],
      status: await statusDao.getNameById(map["status_id"]),
      processingPercentage:
          (map["processing_percentage"] as num?)?.toDouble() ?? 100.0,
      preparationPercentage:
          (map["preparation_percentage"] as num?)?.toDouble() ?? 100.0,
      restPercentage: (map["rest_percentage"] as num?)?.toDouble() ?? 100.0,
      continueCapacity: map["continue_capacity"] ?? 0,
      name: map["machine_name"],
      availabilityDateTime: map["availability_time"] != null
          ? DateTime.tryParse(map["availability_time"].toString())
          : null,
      scheduledInactivities: scheduled,
    );
  }

  Future<List<MachineInactivityEntity>> _getMachineInactivities(
      int machineId) async {
    final rows = await machineInactivityDao.getByMachineId(machineId);
    return rows.map(MachineInactivityEntity.fromDatabaseMap).toList();
  }

  String? _durationToSqlTime(Duration? duration) {
    if (duration == null) return null;
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes - (duration.inHours * 60))
        .toString()
        .padLeft(2, '0');
    return '1970-01-01 $hours:$minutes:00';
  }

  @override
  Future<Either<Failure, bool>> updateAutomaticInactivity({
    required int machineId,
    required int continueCapacity,
    Duration? restTime,
  }) async {
    try {
      final updated = await machineDao.updateMachine(machineId, {
        'continue_capacity': continueCapacity,
        'rest_time': _durationToSqlTime(restTime),
      });
      return Right(updated);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, List<MachineInactivityEntity>>> getMachineInactivities(
      int machineId) async {
    try {
      final rows = await machineInactivityDao.getByMachineId(machineId);
      return Right(rows.map(MachineInactivityEntity.fromDatabaseMap).toList());
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, MachineInactivityEntity>> insertMachineInactivity(
      MachineInactivityEntity inactivity) async {
    try {
      final id = await machineInactivityDao.insert(inactivity.toDatabaseMap());
      return Right(inactivity.copyWith(id: id));
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, MachineInactivityEntity>> updateMachineInactivity(
      MachineInactivityEntity inactivity) async {
    try {
      if (inactivity.id == null) {
        throw LocalStorageFailure();
      }
      final updated = await machineInactivityDao.update(
        inactivity.id!,
        inactivity.toDatabaseMap(),
      );
      return updated ? Right(inactivity) : Left(LocalStorageFailure());
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, bool>> deleteMachineInactivity(
      int inactivityId) async {
    try {
      final deleted = await machineInactivityDao.delete(inactivityId);
      return Right(deleted);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }
}
