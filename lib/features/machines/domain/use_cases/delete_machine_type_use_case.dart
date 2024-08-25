import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class DeleteMachineTypeUseCase extends UseCase<bool, int>{

  final MachineRepository repository;

  DeleteMachineTypeUseCase({required this.repository});

  @override
  Future<Either<Failure, bool>> call({required int p}) {
    // TODO: implement call
    throw UnimplementedError();
  }
}