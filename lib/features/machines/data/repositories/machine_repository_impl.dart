import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/data/dao_implementations/machine_type_dao_sqllite.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_type_dao.dart';
import 'package:production_planning/features/machines/data/models/machine_type_model.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class MachineRepositoryImpl implements MachineRepository{

  final MachineTypeDao machineDao;

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

//need to check if it's good to get only the ID or if it could be better to get the entire entry
  @override
  Future<Either<Failure, int>> insertMachine(MachineTypeEntity machine) async {
    try{
      int id = await machineDao.insertMachine(MachineTypeModel.fromEntity(machine));
      return Right(id);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }

}