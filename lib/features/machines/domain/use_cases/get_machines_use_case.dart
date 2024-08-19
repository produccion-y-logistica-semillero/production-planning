
import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class GetMachinesUseCase implements UseCase<List<MachineEntity>, void>{

  final MachineRepository repository;

  GetMachinesUseCase({required this.repository});
  
  @override
  Future<Either<Failure,List<MachineEntity>>> call({void p}) async {
    return Right([]);
  }
}