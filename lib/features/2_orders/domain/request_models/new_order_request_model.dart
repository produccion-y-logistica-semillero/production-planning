class NewOrderRequestModel{
  final int sequenceId;
  final DateTime dueDate;
  final int priority;
  final int amount;

  NewOrderRequestModel(this.sequenceId, this.dueDate, this.priority, this.amount);
}