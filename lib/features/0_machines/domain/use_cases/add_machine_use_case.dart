import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';

class AddMachineUseCase implements UseCase<MachineEntity, Map<String, dynamic>> {
  final MachineRepository repository;

  AddMachineUseCase({required this.repository});

  @override
  Future<Either<Failure, MachineEntity>> call({required Map<String, dynamic> p}) async{
    final machine = MachineEntity(
      status          : p["status_id"], 
      processingTime  : p["processing_time"], 
      preparationTime : p["preparation_time"], 
      restTime        : p["rest_time"], 
      continueCapacity: p["continue_capacity"]);
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