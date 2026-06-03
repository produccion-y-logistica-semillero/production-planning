import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/job_interruption_policy.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_times.dart';

/// Returns the explicit Duration for [job]-[taskId]-[machine] when available.
/// Tries the following fallbacks in order:
/// 1. inner[machine.id]
/// 2. inner[machine.machineTypeId]
/// 3. if inner has exactly one entry, return that value
/// 4. null if nothing found
MachineTimes? getExplicitMachineTimes(
    JobEntity job, int taskId, MachineEntity machine) {
  if (job.taskMachineTimes == null) return null;
  final inner = job.taskMachineTimes![taskId];
  if (inner == null || inner.isEmpty) return null;

  // 1. Try machine.id
  if (machine.id != null && inner.containsKey(machine.id)) {
    return inner[machine.id];
  }

  // 2. Try machineTypeId
  if (machine.machineTypeId != null &&
      inner.containsKey(machine.machineTypeId)) {
    return inner[machine.machineTypeId];
  }

  // 3. If only one mapping exists, return it (best-effort)
  if (inner.length == 1) {
    return inner.values.first;
  }

  return null;
}

/// Returns the explicit processing Duration for [job]-[taskId]-[machine] when available.
/// This is a convenience function that extracts only the processing time from MachineTimes.
Duration? getExplicitProcessingDuration(
    JobEntity job, int taskId, MachineEntity machine) {
  final machineTime = getExplicitMachineTimes(job, taskId, machine);
  return machineTime?.processing;
}

String _normalizeMachineName(String machineName) {
  return machineName.trim().toLowerCase();
}

/// Converts an order-level setup matrix keyed by machine name into a matrix keyed by machine id.
Map<int, Map<String, Map<String, int>>>? buildMachineStateSetupMatrix(
  List<MachineEntity> machines,
  Map<String, Map<String, Map<String, int>>>? orderSetupMatrix,
) {
  if (orderSetupMatrix == null || orderSetupMatrix.isEmpty) {
    return null;
  }

  final normalizedOrderMatrix = <String, Map<String, Map<String, int>>>{};
  for (final entry in orderSetupMatrix.entries) {
    normalizedOrderMatrix[_normalizeMachineName(entry.key)] = entry.value;
  }

  final result = <int, Map<String, Map<String, int>>>{};
  for (final machine in machines) {
    if (machine.id == null) continue;
    final matrixForMachine = normalizedOrderMatrix[_normalizeMachineName(machine.name)];
    if (matrixForMachine != null) {
      result[machine.id!] = matrixForMachine;
    }
  }

  return result.isEmpty ? null : result;
}

/// Builds machine state mapping for each job keyed by actual machine id.
Map<int, Map<int, String>> buildJobMachineStates(
  List<JobEntity> jobs,
  List<MachineEntity> machines,
) {
  final result = <int, Map<int, String>>{};
  for (final job in jobs) {
    if (job.jobId == null || job.machineFinalStates == null) continue;
    final jobStates = <int, String>{};
    for (final machine in machines) {
      final machineTypeId = machine.machineTypeId;
      if (machine.id == null || machineTypeId == null) continue;
      final state = job.machineFinalStates![machineTypeId];
      if (state != null && state.isNotEmpty) {
        jobStates[machine.id!] = state;
      }
    }
    if (jobStates.isNotEmpty) {
      result[job.jobId!] = jobStates;
    }
  }
  return result;
}

/// Builds per-job interruption policies keyed by database job id.
Map<int, JobInterruptionPolicy> buildJobInterruptionPolicies(
  List<JobEntity> jobs,
) {
  final result = <int, JobInterruptionPolicy>{};
  for (final job in jobs) {
    if (job.jobId == null) continue;
    result[job.jobId!] =
        job.interruptionPolicy ?? JobInterruptionPolicy.legacyDefault;
  }
  return result;
}
