import 'package:production_planning/entities/environment_entity.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';

abstract class GanttState{

  int? orderId;
  int? selectedRule;
  final EnvironmentEntity? enviroment;
  GanttState(this.orderId, this.enviroment, this.selectedRule);
}

class GanttInitialState extends GanttState{
  GanttInitialState(super.orderId, super.enviroment, super.selectedRule);
}

class GanttOrderRetrieved  extends GanttState{
  GanttOrderRetrieved(super.orderId, super.enviroment, super.selectedRule);
}

class GanttOrderRetrieveError extends GanttState{
  GanttOrderRetrieveError(super.orderId, super.enviroment, super.selectedRule);
}

class GanttPlanningLoading extends GanttState{
  GanttPlanningLoading(super.orderId, super.enviroment, super.selectedRule);
}

class GanttPlanningError extends GanttState{
  GanttPlanningError(super.orderId, super.enviroment, super.selectedRule);
}

class GanttPlanningSuccess extends GanttState{
  List<PlanningMachineEntity> planningMachines;
  Metrics metrics;
  
  GanttPlanningSuccess(super.orderId, super.enviroment, this.planningMachines, this.metrics, super.selectedRule);
}

