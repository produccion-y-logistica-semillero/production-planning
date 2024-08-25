
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class AddMachineUseCase implements UseCase<MachineTypeEntity, Map<String, dynamic>>{

  final MachineRepository repository;

  AddMachineUseCase({required this.repository});

  @override
  Future<Either<Failure, MachineTypeEntity>> call({required p}) async {
    final machine = MachineTypeEntity(name: p["name"], description: p["description"]);
    final response = await repository.insertMachine(machine);
    return response.fold(
      (f) => Left(f),
      (id) {
        machine.id = id;
        return Right(machine);
      }
      ); 
  }
} 