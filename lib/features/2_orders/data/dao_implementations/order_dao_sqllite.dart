import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/order_dao.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:sqflite/sqflite.dart';
import 'package:production_planning/features/2_orders/data/models/order_model.dart';

class OrderDaoSqlLite implements OrderDao {
  final Database db;

  OrderDaoSqlLite(this.db);

  @override
  Future<List<OrderModel>> getAllOrders() async {
    try{
      final List<Map<String, dynamic>> maps = await db.query('orders');
      return maps.map((map) => OrderModel.fromJson(map)).toList();
    }catch(error){
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<OrderModel> getOrderById(int id) async{
    try{
      return (await db.query('orders', where: 'order_id = ?', whereArgs: [id])).map((json)=>OrderModel.fromJson(json)).first;
    }catch(error){
      throw LocalStorageFailure();
    }
  }

  @override
  Future<int> insertOrder(OrderEntity order) async {
    try {
      // this only send reg_date to data base because the id is automatically generated, and the list isn't part of orders table.
      final orderMap = {
        'reg_date': order.regDate.toIso8601String(),
      };

      final orderId = await db.insert('orders', orderMap);

      return orderId;
    } catch (error) {
      print("ERROR AL INSERTAR ORDEN EN DAO: ${error.toString()}");
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<int> getOrderByTaskId(int taskId) async {
    try {
      final result = await db.rawQuery(
        '''
        SELECT o.order_id 
        FROM orders o 
        INNER JOIN tasks t 
        ON t.order_id = o.order_id 
        WHERE t.task_id = ? 
        LIMIT 1
        ''', 
        [taskId]
      );

      if (result.isNotEmpty) {
        return result.first['order_id'] as int;
      } else {
        throw LocalStorageFailure();
      }
    } catch (error) {
      throw LocalStorageFailure();
    }
  }

}
