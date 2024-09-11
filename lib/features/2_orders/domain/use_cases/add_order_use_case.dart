import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/request_models/new_order_request_model.dart';

class AddOrderUseCase implements UseCase<OrderEntity, List<NewOrderRequestModel>>{

  @override
  Future<Either<Failure, OrderEntity>> call({required List<NewOrderRequestModel> p}) {
    // TODO: implement call
    throw UnimplementedError();
  }
}