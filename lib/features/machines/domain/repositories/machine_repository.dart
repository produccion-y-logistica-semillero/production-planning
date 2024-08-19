import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';

abstract class MachineRepository{

  Future<Either<Failure, List<MachineEntity>>> getAllMachines();

  Future<Either<Failure, bool>> insertMachine(MachineEntity machine);
  
}