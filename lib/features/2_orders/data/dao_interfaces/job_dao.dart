import 'package:production_planning/features/2_orders/data/models/job_model.dart';

abstract class JobDao {
  Future<List<JobModel>> getJobsByOrderId(int orderId);
}
