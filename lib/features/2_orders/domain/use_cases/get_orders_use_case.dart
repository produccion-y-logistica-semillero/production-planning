import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';

class GetOrdersUseCase implements UseCase<List<OrderEntity>, void> {
  final OrderRepository repository;


  GetOrdersUseCase({required this.repository});

  @override
  Future<Either<Failure, List<OrderEntity>>> call({required void p}) async {
    return repository.getAllOrders();
  }
}
