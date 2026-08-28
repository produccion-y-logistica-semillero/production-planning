// lib/entities/order_entity.dart
//
// setupTimeMatrix is provided by the caller (the new-order wizard's BLoC
// state) when creating/updating an order, and is persisted in the
// order_setup_matrix table by OrderDao. Adapters then call the helper
// functions in shared/functions/functions.dart (buildMachineStateSetupMatrix
// / buildJobMachineStates) using this field, read back from the DB.

import 'package:production_planning/entities/job_entity.dart';

class OrderEntity {
  final int? orderId;
  final DateTime regDate;
  List<JobEntity>? orderJobs;

  /// Map<machineName, fromState -> toState -> minutes> persisted with the order.
  /// Used by adapters to build the state-based setup matrix and job states.
  final Map<String, Map<String, Map<String, int>>>? setupTimeMatrix;

  OrderEntity(
    this.orderId,
    this.regDate,
    this.orderJobs, {
    this.setupTimeMatrix,
  });
}