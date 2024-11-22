import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';

class DeleteOrderUseCase implements UseCase<bool, int>{

  final OrderRepository repo;

  DeleteOrderUseCase(this.repo);
  
  @override
  Future<Either<Failure, bool>> call({required int p}) async{
    return await repo.deleteOrder(p);
  }
  
}