
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class AddMachineUseCase implements UseCase<MachineEntity, dynamic>{

  final MachineRepository repository;

  AddMachineUseCase({required this.repository});

  @override
  Future<Either<Failure, MachineEntity>> call({p}) async {
    final machine = MachineEntity(name: p["name"], description: p["description"]);

    return Right(machine);
  }
} 