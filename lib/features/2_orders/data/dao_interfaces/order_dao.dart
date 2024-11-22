import 'package:production_planning/features/2_orders/data/models/order_model.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';

abstract class OrderDao {
  Future<List<OrderModel>> getAllOrders();
  Future<OrderModel> getOrderById(int id);
  Future<int> insertOrder(OrderEntity order);
  Future<int> getOrderByTaskId(int taskId);
}
