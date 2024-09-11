import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';
import 'package:production_planning/features/1_sequences/domain/repositories/sequences_repository.dart';

class GetSequencesUseCase implements UseCase<List<SequenceEntity>,void>{

  final SequencesRepository repository;

  GetSequencesUseCase(this.repository);

  @override
  Future<Either<Failure, List<SequenceEntity>>> call({required p}) {
    return repository.getBasicSequences();
  }
  
}