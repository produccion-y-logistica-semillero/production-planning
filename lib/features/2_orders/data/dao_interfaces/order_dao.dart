import 'package:production_planning/features/2_orders/data/models/order_model.dart';

abstract class OrderDao {
  Future<List<OrderModel>> getAllOrders();
}
