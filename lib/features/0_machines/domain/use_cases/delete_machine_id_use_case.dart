import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';

class DeleteMachineUseCase implements UseCase<bool, int> {
  final MachineRepository repository;

  DeleteMachineUseCase({required this.repository});

  @override
  Future<Either<Failure, bool>> call({required int p}) async {
    final response = await repository.deleteMachine(p);
    return response.fold(
      (f) => Left(f),
      (success) => Right(success),
    );
  }
}
