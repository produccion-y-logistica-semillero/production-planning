import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/sequences/domain/request_models/new_task_model.dart';

class AddSequenceUseCase implements UseCase<bool, List<NewTaskModel>>{

  @override
  Future<Either<Failure, bool>> call({required List<NewTaskModel> p}) {
    // TODO: implement call
    throw UnimplementedError();
  }
}