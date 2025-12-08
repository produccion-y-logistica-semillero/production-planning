import 'package:production_planning/repositories/models/order_model.dart';
import 'package:production_planning/entities/order_entity.dart';

abstract class OrderDao {
  Future<List<OrderModel>> getAllOrders();
  Future<OrderModel> getOrderById(int id);
  Future<int> insertOrder(OrderEntity order);
  Future<void> deleteOrder(int orderId);
}
