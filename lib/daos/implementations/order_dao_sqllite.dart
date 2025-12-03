import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/order_dao.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:sqflite/sqflite.dart';
import 'package:production_planning/repositories/models/order_model.dart';

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
  Future<void> deleteOrder(int orderId) async{
    try {
      int n = await db.delete(
        'ORDERS',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
    } catch (error) {
      throw LocalStorageFailure();
    }
  }
}
