import 'package:dartz/dartz.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/add_job.dart';


sealed class NewOrderState{
    NewOrderState();
}

class NewOrdersInitialState extends NewOrderState{
  NewOrdersInitialState();
}

class NewOrdersFailureState extends NewOrderState{
  NewOrdersFailureState();
}

class NewOrdersState extends NewOrderState{
  final List<AddJobWidget> jobs;
  final List<Tuple2<int, String>> sequences;
  bool? justSaved;
  NewOrdersState(this.jobs, this.sequences);
}


