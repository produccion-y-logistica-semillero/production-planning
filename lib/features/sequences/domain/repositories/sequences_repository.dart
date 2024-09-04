import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/sequences/domain/entities/job_entity.dart';

abstract class SequencesRepository{
  Future<Either<Failure, bool>> createSequence(JobEntity job);
}