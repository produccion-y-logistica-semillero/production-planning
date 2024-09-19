import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/2_orders/data/repositories/order_repository_impl.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';

class GetOrdersUseCase implements UseCase<List<OrderEntity>, void> {
  final OrderRepositoryImpl repository;

  GetOrdersUseCase({required this.repository});

  @override
  Future<Either<Failure, List<OrderEntity>>> call({required void p}) async {
    return repository.getAllOrders();
  }
}
