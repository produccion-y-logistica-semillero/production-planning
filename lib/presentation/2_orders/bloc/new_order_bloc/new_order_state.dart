import 'package:dartz/dartz.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/add_job.dart';

/// How availableDate/dueDate are determined for the jobs of an order being
/// created or edited.
enum DateRegistrationMode {
  /// User picks availableDate/dueDate per job (current/original behavior).
  manual,

  /// availableDate = order registration date; dueDate = availableDate +
  /// [NewOrdersState.leadTimeDays].
  automatic,
}

sealed class NewOrderState {
  NewOrderState();
}

class NewOrdersInitialState extends NewOrderState {
  NewOrdersInitialState();
}

class NewOrdersFailureState extends NewOrderState {
  NewOrdersFailureState();
}

class NewOrdersState extends NewOrderState {

  final List<AddJobWidget> jobs;
  final List<Tuple2<int, String>> sequences;
  bool? justSaved;

  Map<String, Map<String, Map<String, int>>>? setupTimeMatrix;

  final DateRegistrationMode dateMode;
  final int leadTimeDays;

  NewOrdersState({
    required this.jobs,
    required this.sequences,
    this.justSaved,
    this.setupTimeMatrix,
    this.dateMode = DateRegistrationMode.manual,
    this.leadTimeDays = 3,
  });

  NewOrdersState copyWith({
    List<AddJobWidget>? jobs,
    List<Tuple2<int, String>>? sequences,
    bool? justSaved,
    Map<String, Map<String, Map<String, int>>>? setupTimeMatrix,
    DateRegistrationMode? dateMode,
    int? leadTimeDays,
  }) => NewOrdersState(
    jobs: jobs ?? this.jobs,
    sequences: sequences ?? this.sequences,
    justSaved: justSaved ?? this.justSaved,
    setupTimeMatrix: setupTimeMatrix ?? this.setupTimeMatrix,
    dateMode: dateMode ?? this.dateMode,
    leadTimeDays: leadTimeDays ?? this.leadTimeDays,
  );
}
