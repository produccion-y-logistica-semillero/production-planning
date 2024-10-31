import 'package:production_planning/features/2_orders/data/models/job_model.dart';
import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';

abstract class JobDao {
  Future<List<JobModel>> getJobsByOrderId(int orderId);
  Future<void> insertJob(JobEntity job);
}
