abstract class GanttEvent{
}

class AssignOrderId extends GanttEvent{
  final int id;
  AssignOrderId(this.id);
}

class SelectRule extends GanttEvent{
  final int id;
  SelectRule(this.id);
}