import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/data/dao_implementations/machine_dao_sqllite.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/machines/data/models/machine_model.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class MachineRepositoryImpl implements MachineRepository{

  final MachineDao machineDao;

  MachineRepositoryImpl({required this.machineDao});

  @override
  Future<Either<Failure, List<MachineTypeEntity>>> getAllMachines() async {
    try{
      return Right(
        (await machineDao.getAllMachines())
          .map((model)=> model.toEntity())
          .toList()
      );
    }
    on Failure catch(failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, int>> insertMachine(MachineTypeEntity machine) async {
    try{
      int id = await machineDao.insertMachine(MachineModel.fromEntity(machine));
      return Right(id);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }

}