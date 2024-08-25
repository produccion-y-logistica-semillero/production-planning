
import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class GetMachineTypesUseCase implements UseCase<List<MachineTypeEntity>, void>{

  final MachineRepository repository;

  GetMachineTypesUseCase({required this.repository});
  
  @override
  Future<Either<Failure,List<MachineTypeEntity>>> call({void p}) async {
    return repository.getAllMachines();
  }
}