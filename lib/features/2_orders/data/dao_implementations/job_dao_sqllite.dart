import 'package:production_planning/features/2_orders/data/dao_interfaces/job_dao.dart';
import 'package:production_planning/features/2_orders/data/models/job_model.dart';
import 'package:sqflite/sqflite.dart';

class JobDaoSQLlite implements JobDao {
  final Database db;

  JobDaoSQLlite(this.db);

  @override
  Future<List<JobModel>> getJobsByOrderId(int orderId) async {
    final List<Map<String, dynamic>> maps = await db.query(
      'jobs',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    return maps.map((map) => JobModel.fromJson(map)).toList();
  }
}
