import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/environment_entity.dart';
import 'package:production_planning/entities/order_entity.dart';

abstract class OrderRepository{
  Future<Either<Failure, List<OrderEntity>>> getAllOrders() ;

  Future<Either<Failure, OrderEntity>> getFullOrder(int id);


  Future<Either<Failure, EnvironmentEntity>> getEnvironmentByName(String name);

  Future<Either<Failure, bool>> createOrder(OrderEntity orderEntity);

  Future<Either<Failure, bool>> deleteOrder(int orderId);
}