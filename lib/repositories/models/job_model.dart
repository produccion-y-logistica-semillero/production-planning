
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/machine_times.dart';

class JobModel {
  final int jobId;
  final int sequenceId;
  final int amount;
  final String? jobName;
  final DateTime dueDate;
  final DateTime availableDate;
  final int priority;
  final String? jobState;

  final Map<int, int>? preemptionMatrix;
  // Map<taskId, Map<machineId, Map<'processing'|'preparation'|'rest', minutes>>>
  final Map<int, Map<int, Map<String, int>>>? taskMachineTimesMinutes;
  final Map<int, String>? machineFinalStates;

  JobModel(this.jobId, this.sequenceId, this.amount, this.jobName, this.dueDate,
      this.priority, this.availableDate,
      {this.preemptionMatrix, this.taskMachineTimesMinutes, this.jobState, this.machineFinalStates});

  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
        json['job_id'],
        json['sequence_id'],
        json['amount'],
        json['job_name'],
        DateTime.parse(json['due_date']),
        json['priority'],
        DateTime.parse(json['available_date']),
        jobState: json['job_state'] as String?);
  }
  JobEntity toEntity() {
    // Convert minutes map to MachineTimes map.
    // taskMachineTimesMinutes stores time durations as minutes (integers)
    // and must be converted to MachineTimes objects with Duration instances.
    Map<int, Map<int, MachineTimes>>? taskTimes;
    if (taskMachineTimesMinutes != null) {
      taskTimes = {};
      taskMachineTimesMinutes!.forEach((taskId, mm) {
        final inner = <int, MachineTimes>{};
        mm.forEach((machineId, mMap) {
          inner[machineId] = MachineTimes(
            processing: Duration(minutes: mMap['processing'] ?? 0),
            preparation: Duration(minutes: mMap['preparation'] ?? 0),
            rest: Duration(minutes: mMap['rest'] ?? 0),
          );
        });
        taskTimes![taskId] = inner;
      });
    }

    return JobEntity(jobId, null, amount, jobName, dueDate, priority, availableDate,
        preemptionMatrix: preemptionMatrix, taskMachineTimes: taskTimes, machineFinalStates: machineFinalStates);

  }
}
