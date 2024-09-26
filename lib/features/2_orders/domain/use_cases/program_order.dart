import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';


//by now it will return void, in the future we need to adapt to the programming entity or something like that
class ProgramOrder implements UseCase<void, List<dynamic>>{
  @override
  Future<Either<Failure, void>> call({required List p}) {
    throw UnimplementedError();
  }

}