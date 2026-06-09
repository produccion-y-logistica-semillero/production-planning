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

    try {
      final List<Map<String, dynamic>> maps = await db.query('orders');
      List<OrderModel> orders = [];
      for (var map in maps) {
        final orderId = map['order_id'] as int;
        final matrixMaps = await db.query(
          'order_setup_matrix',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
        Map<String, Map<String, Map<String, int>>>? matrix;
        if (matrixMaps.isNotEmpty) {
          matrix = {};
          for (var mm in matrixMaps) {
            final m = mm['machine_name'] as String;
            final from = mm['from_state'] as String;
            final to = mm['to_state'] as String;
            final dur = mm['duration_minutes'] as int;
            matrix.putIfAbsent(m, () => {}).putIfAbsent(from, () => {})[to] = dur;
          }
        }
        orders.add(OrderModel(
          orderId,
          DateTime.parse(map['reg_date']),
          setupTimeMatrix: matrix,
        ));
      }
      return orders;
    } catch (error) {
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<OrderModel> getOrderById(int id) async {
    try {
      final map = (await db.query('orders', where: 'order_id = ?', whereArgs: [id])).first;
      final matrixMaps = await db.query(
        'order_setup_matrix',
        where: 'order_id = ?',
        whereArgs: [id],
      );
      Map<String, Map<String, Map<String, int>>>? matrix;
      if (matrixMaps.isNotEmpty) {
        matrix = {};
        for (var mm in matrixMaps) {
          final m = mm['machine_name'] as String;
          final from = mm['from_state'] as String;
          final to = mm['to_state'] as String;
          final dur = mm['duration_minutes'] as int;
          matrix.putIfAbsent(m, () => {}).putIfAbsent(from, () => {})[to] = dur;
        }
      }
      return OrderModel(
        map['order_id'] as int,
        DateTime.parse(map['reg_date'] as String),
        setupTimeMatrix: matrix,
      );
    } catch (error) {

      throw LocalStorageFailure();
    }
  }

  @override
  Future<int> insertOrder(OrderEntity order) async {
    try {
      return await db.transaction<int>((txn) async {
        // this only send reg_date to data base because the id is automatically generated, and the list isn't part of orders table.
        final orderMap = {
          'reg_date': order.regDate.toIso8601String(),
        };

        final orderId = await txn.insert('orders', orderMap);

        if (order.setupTimeMatrix != null) {
          for (var mEntry in order.setupTimeMatrix!.entries) {
            for (var entry in mEntry.value.entries) {
              for (var subEntry in entry.value.entries) {
                await txn.insert('order_setup_matrix', {
                  'order_id': orderId,
                  'machine_name': mEntry.key,
                  'from_state': entry.key,
                  'to_state': subEntry.key,
                  'duration_minutes': subEntry.value,
                });
              }
            }
          }
        }

        return orderId;
      });
    } catch (error) {
      print("ERROR AL INSERTAR ORDEN EN DAO: ${error.toString()}");
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<void> deleteOrder(int orderId) async{
    try {
      await db.delete(
        'order_setup_matrix',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      await db.delete(
        'orders',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
    } catch (error) {
      throw LocalStorageFailure();
    }
  }
}
