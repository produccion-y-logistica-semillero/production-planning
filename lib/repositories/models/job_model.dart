import 'package:production_planning/entities/job_entity.dart';

class JobModel {
  final int jobId;
  final int sequenceId;
  final int amount;
  final DateTime dueDate;
  final DateTime availableDate;
  final int priority;
  final Map<int, int>? preemptionMatrix;
  // Map<taskId, Map<machineId, Map<'processing'|'preparation'|'rest', minutes>>>
  final Map<int, Map<int, Map<String, int>>>? taskMachineTimesMinutes;

  JobModel(this.jobId, this.sequenceId, this.amount, this.dueDate,
      this.priority, this.availableDate,
      {this.preemptionMatrix, this.taskMachineTimesMinutes});

  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
        json['job_id'],
        json['sequence_id'],
        json['amount'],
        DateTime.parse(json['due_date']),
        json['priority'],
        DateTime.parse(json['available_date']));
  }
  JobEntity toEntity() {
    // convert minutes map to MachineTimes map
    Map<int, Map<int, dynamic>>? taskTimes;
    if (taskMachineTimesMinutes != null) {
      taskTimes = {};
      taskMachineTimesMinutes!.forEach((taskId, mm) {
        final inner = <int, dynamic>{};
        mm.forEach((machineId, mMap) {
          final processing = Duration(minutes: mMap['processing'] ?? 0);
          final preparation = Duration(minutes: mMap['preparation'] ?? 0);
          final rest = Duration(minutes: mMap['rest'] ?? 0);
          inner[machineId] = (processing, preparation, rest);
        });
        taskTimes![taskId] = inner;
      });
    }

    // Note: JobEntity.taskMachineTimes expects MachineTimes objects; conversion
    // to MachineTimes is handled later in repository implementation where
    // sequence/tasks are available.
    return JobEntity(jobId, null, amount, dueDate, priority, availableDate,
        preemptionMatrix: preemptionMatrix, taskMachineTimes: null);
  }
}
