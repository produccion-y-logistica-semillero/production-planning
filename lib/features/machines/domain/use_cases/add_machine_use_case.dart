
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';

class AddMachineUseCase implements UseCase<MachineEntity, dynamic>{

  @override
  Future<Either<Failure, MachineEntity>> call({p}) async {
    final machine = MachineEntity(name: p["name"], description: p["description"]);

    return Right(machine);
  }
} 