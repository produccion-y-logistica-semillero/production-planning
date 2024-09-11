import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';
import 'package:production_planning/features/1_sequences/domain/repositories/sequences_repository.dart';

class GetSequenceUseCase implements UseCase<SequenceEntity?, int>{

  final SequencesRepository repository;

  GetSequenceUseCase(this.repository);

  @override
  Future<Either<Failure, SequenceEntity?>> call({required p}){
    return repository.getFullSequence(p);
  }

}