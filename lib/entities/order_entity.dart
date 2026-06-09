// lib/entities/order_entity.dart
//
// Change: adds optional setupTimeMatrix field.
// This is populated by OrdersService.scheduleOrder() just before calling
// an adapter, by reading SetupTimeService.allCachedMatrices.
// Adapters then call the helper functions in shared/functions/functions.dart
// (buildMachineStateSetupMatrix / buildJobMachineStates) using this field.

import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/services/setup_time_matrix.dart';

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