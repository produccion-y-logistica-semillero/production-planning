import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/data/dao_implementations/machine_type_dao_sqllite.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_type_dao.dart';
import 'package:production_planning/features/machines/data/models/machine_type_model.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class MachineRepositoryImpl implements MachineRepository{

  final MachineTypeDao machineTypeDao;
  final MachineDao machineDao;

  MachineRepositoryImpl({required this.machineTypeDao, required this.machineDao});

  @override
  Future<Either<Failure, List<MachineTypeEntity>>> getAllMachineTypes() async {
    try{
      return Right(
        (await machineTypeDao.getAllMachines())
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
  Future<Either<Failure, int>> insertMachineType(MachineTypeEntity machine) async {
    try{
      int id = await machineTypeDao.insertMachine(MachineTypeModel.fromEntity(machine));
      return Right(id);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, bool>> deleteMachineType(int id) async{
    try{
      await machineDao.deleteWhere(machineTypeDao.getTablePK(), id);  //we delete first all the machines associated with that machine type
      await machineTypeDao.deleteMachine(id);
      return Right (true);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, List<MachineEntity>>> getAllMachinesFromType(int machineTypeId) {
    // TODO: implement getAllMachinesFromType
    throw UnimplementedError();
  }

  //Machines Specific Implementations

  Future<Either<Failure, bool>> deleteMachine(int id) async{
    try{
      await machineDao.delete(id);
      return Right(true);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }

}