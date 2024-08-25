import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';

abstract class MachineRepository{

  Future<Either<Failure, List<MachineTypeEntity>>> getAllMachines();

  Future<Either<Failure, int>> insertMachine(MachineTypeEntity machine);
  
}