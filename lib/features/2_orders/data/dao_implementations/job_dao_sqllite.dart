import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/job_dao.dart';
import 'package:production_planning/features/2_orders/data/models/job_model.dart';
import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';
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

  @override
  Future<void> insertJob(JobEntity job, int orderId) async {
    try {
      // map job data for data base
      final jobMap = {
        'sequence_id': job.sequence!.id,
        'order_id': orderId,
        'amount': job.amount,
        'due_date': job.dueDate.toIso8601String(), // due date
        'priority': job.priority,
        'available_date': job.availableDate.toIso8601String(),
      };

      // insert job to data base
      await db.insert('jobs', jobMap);
    } catch (error) {
      print("ERROR AL INSERTAR JOB EN DAO: ${error.toString()}");
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<void> deleteJobsFromOrder(int orderId) async{
    try {
      int n = await db.delete(
        'JOBS',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
    } catch (error) {
      throw LocalStorageFailure();
    }
  }
}
