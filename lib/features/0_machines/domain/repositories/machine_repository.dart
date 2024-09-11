import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';

abstract class MachineRepository{

  Future<Either<Failure, List<MachineTypeEntity>>> getAllMachineTypes();

  Future<Either<Failure, int>> insertMachineType(MachineTypeEntity machine);

  Future<Either<Failure, bool>> deleteMachineType(int id);

  Future<Either<Failure, List<MachineEntity>>> getAllMachinesFromType(int machineTypeId);

  Future<Either<Failure, bool>> deleteMachine(int id);
  
}