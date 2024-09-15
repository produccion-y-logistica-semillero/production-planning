import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/1_sequences/domain/repositories/sequences_repository.dart';

class DeleteSequenceUseCase implements UseCase<bool, int>{

  final SequencesRepository repo;

  DeleteSequenceUseCase(this.repo);

  @override
  Future<Either<Failure, bool>> call({required int p}) {
    return repo.deleteSequence(p);
  }
}