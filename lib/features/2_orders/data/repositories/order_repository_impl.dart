import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/order_dao.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/job_dao.dart';
import 'package:production_planning/features/2_orders/domain/entities/environment_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';

class OrderRepositoryImpl implements OrderRepository{
  final OrderDao orderDao;
  final JobDao jobDao;

  OrderRepositoryImpl({required this.orderDao, required this.jobDao});

  @override
  Future<Either<Failure, List<OrderEntity>>> getAllOrders() async {
    try {
      // 1. Obtener todas las órdenes
      final orderModels = await orderDao.getAllOrders();
      List<OrderEntity> orders = [];

      for (var orderModel in orderModels) {
        // 2. Obtener todos los trabajos asociados a la orden
        final jobModels = await jobDao.getJobsByOrderId(orderModel.orderId!);

        // 3. Convertir los modelos a entidades
        List<JobEntity> jobs =
            jobModels.map((jobModel) => jobModel.toEntity()).toList();

        // 4. Crear la entidad de orden y agregarla a la lista
        orders.add(orderModel.toEntity(jobs));
      }

      return Right(orders);
    } on Failure catch (error) {
      return Left(error);
    }
  }

  @override
  Future<Either<Failure, EnvironmentEntity>> getEnvironmentByName(String name) {
    // TODO: implement getEnvironmentByName
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, OrderEntity>> getFullOrder(int id) {
    // TODO: implement getFullOrder
    throw UnimplementedError();
  }
}
