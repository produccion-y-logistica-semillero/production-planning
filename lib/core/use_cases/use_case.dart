import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';

abstract class UseCase<ReturnT,  Params>{
  Future<Either<Failure, ReturnT>> call({required Params p});
}