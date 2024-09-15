import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';

abstract class SequencesRepository{
  Future<Either<Failure, bool>> createSequence(SequenceEntity sequence);
  Future<Either<Failure, List<SequenceEntity>>> getBasicSequences();
  Future<Either<Failure, SequenceEntity?>> getFullSequence(int id);
  Future<Either<Failure, bool>> deleteSequence(int id);
}