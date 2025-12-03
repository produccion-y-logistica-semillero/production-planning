import 'package:production_planning/entities/order_entity.dart';

abstract class TaskState{}

class TaskInitialState implements  TaskState{}

class TaskRetrievedState implements TaskState{
  final OrderEntity order;
TaskRetrievedState(this.order);
}

class TaskErrorState implements TaskState{}


class TaskRetrievingState implements TaskState{}