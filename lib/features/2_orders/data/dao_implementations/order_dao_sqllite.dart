import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/order_dao.dart';
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
}
