class NewOrderRequestModel{
  final int sequenceId;
  final DateTime dueDate;
  final DateTime availableDate;
  final int priority;
  final int amount;
  final Map<int, int>? preemptionMatrix;

  NewOrderRequestModel(this.sequenceId, this.dueDate, this.availableDate, this.priority, this.amount, {this.preemptionMatrix});
}
