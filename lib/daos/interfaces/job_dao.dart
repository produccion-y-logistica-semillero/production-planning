import 'package:production_planning/repositories/models/job_model.dart';
import 'package:production_planning/entities/job_entity.dart';

abstract class JobDao {
  Future<List<JobModel>> getJobsByOrderId(int orderId);
  Future<void> insertJob(JobEntity job, int orderId);
  Future<void> deleteJobsFromOrder(int orderId);
}
