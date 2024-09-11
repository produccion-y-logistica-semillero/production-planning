
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';

class AddMachineTypeUseCase implements UseCase<MachineTypeEntity, Map<String, dynamic>>{

  final MachineRepository repository;

  AddMachineTypeUseCase({required this.repository});

  //need to check if it's good to get only the ID or if it could be better to get the entire entry
  @override
  Future<Either<Failure, MachineTypeEntity>> call({required p}) async {
    final machine = MachineTypeEntity(name: p["name"], description: p["description"]);
    final response = await repository.insertMachineType(machine);
    return response.fold(
      (f) => Left(f),
      (id) {
        machine.id = id;
        return Right(machine);
      }
    ); 
  }
} 