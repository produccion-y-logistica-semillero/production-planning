import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/machine_type_entity.dart';

abstract class MachineRepository{

  Future<Either<Failure, List<MachineTypeEntity>>> getAllMachineTypes();

  Future<Either<Failure, int>> insertMachineType(MachineTypeEntity machine);

  Future<Either<Failure, bool>> deleteMachineType(int id);

  Future<Either<Failure, List<MachineEntity>>> getAllMachinesFromType(int machineTypeId);

  Future<Either<Failure, bool>> deleteMachine(int id);

  Future<Either<Failure, int>> insertMachine(MachineEntity machine);

  Future<Either<Failure, int>> countMachinesOf(int machineTypeId);

  Future<Either<Failure, String>> getMachineTypeName(int machineTypeId);

  Future<Either<Failure, bool>> updateAutomaticInactivity({
    required int machineId,
    required int continueCapacity,
    Duration? restTime,
  });

  Future<Either<Failure, List<MachineInactivityEntity>>> getMachineInactivities(int machineId);

  Future<Either<Failure, MachineInactivityEntity>> insertMachineInactivity(MachineInactivityEntity inactivity);

  Future<Either<Failure, MachineInactivityEntity>> updateMachineInactivity(MachineInactivityEntity inactivity);

  Future<Either<Failure, bool>> deleteMachineInactivity(int inactivityId);

}