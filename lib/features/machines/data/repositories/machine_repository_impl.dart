import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/data/data_sources/machine_data_source_sqllite.dart';
import 'package:production_planning/features/machines/data/models/machine_model.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class MachineRepositoryImpl implements MachineRepository{

  final MachineDataSourceSqllite sqlLiteSource;

  MachineRepositoryImpl({required this.sqlLiteSource});

  @override
  Future<Either<Failure, List<MachineEntity>>> getAllMachines() async {
    try{
      return Right(
        (await sqlLiteSource.getAllMachines())
          .map((model)=> model.toEntity())
          .toList()
      );
    }
    on Failure catch(failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, bool>> insertMachine(MachineEntity machine) async {
    try{
      await sqlLiteSource.insertMachine(MachineModel.fromEntity(machine));
      return Right(true);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }

}