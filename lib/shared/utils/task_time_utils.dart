import 'package:production_planning/entities/job_entity.dart';
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
/// 
/// DEBUG: Added logging to track machine name matching for troubleshooting matrix attachment failures.
Map<int, Map<String, Map<String, int>>>? buildMachineStateSetupMatrix(
  List<MachineEntity> machines,
  Map<String, Map<String, Map<String, int>>>? orderSetupMatrix,
) {
  if (orderSetupMatrix == null || orderSetupMatrix.isEmpty) {
    print('DEBUG buildMachineStateSetupMatrix: orderSetupMatrix is null or empty');
    return null;
  }

  print('DEBUG buildMachineStateSetupMatrix:');
  print('  - orderSetupMatrix keys: ${orderSetupMatrix.keys.toList()}');
  print('  - machines available: ${machines.map((m) => m.name).toList()}');

  final normalizedOrderMatrix = <String, Map<String, Map<String, int>>>{};
  for (final entry in orderSetupMatrix.entries) {
    final normalized = _normalizeMachineName(entry.key);
    normalizedOrderMatrix[normalized] = entry.value;
    print('  - normalized matrix key: "${entry.key}" → "$normalized"');
  }

  final result = <int, Map<String, Map<String, int>>>{};
  for (final machine in machines) {
    if (machine.id == null) continue;
    final normalizedMachineName = _normalizeMachineName(machine.name);
    final matrixForMachine = normalizedOrderMatrix[normalizedMachineName];
    print('  - machine "${machine.name}" (id=${machine.id}, normalized="$normalizedMachineName") → match: ${matrixForMachine != null}');
    if (matrixForMachine != null) {
      result[machine.id!] = matrixForMachine;
    }
  }

  print('  - result: ${result.isEmpty ? "EMPTY (no matches)" : "${result.length} machines matched"}');
  return result.isEmpty ? null : result;
}

/// Builds machine state mapping for each job keyed by actual machine id.
/// 
/// DEBUG: Added logging to track job state mapping for troubleshooting matrix attachment failures.
Map<int, Map<int, String>> buildJobMachineStates(
  List<JobEntity> jobs,
  List<MachineEntity> machines,
) {
  print('DEBUG buildJobMachineStates:');
  print('  - total jobs: ${jobs.length}');
  print('  - total machines: ${machines.length}');
  
  final result = <int, Map<int, String>>{};
  for (final job in jobs) {
    if (job.jobId == null || job.machineFinalStates == null) {
      print('  - job ${job.jobId}: skipped (null jobId or machineFinalStates)');
      continue;
    }
    print('  - job ${job.jobId}: machineFinalStates = ${job.machineFinalStates}');
    
    final jobStates = <int, String>{};
    for (final machine in machines) {
      final machineTypeId = machine.machineTypeId;
      if (machine.id == null || machineTypeId == null) continue;
      final state = job.machineFinalStates![machineTypeId];
      if (state != null && state.isNotEmpty) {
        jobStates[machine.id!] = state;
        print('    - machine ${machine.id} (typeId=$machineTypeId): state="$state"');
      }
    }
    if (jobStates.isNotEmpty) {
      result[job.jobId!] = jobStates;
      print('  - job ${job.jobId}: mapped ${jobStates.length} machines');
    } else {
      print('  - job ${job.jobId}: no states mapped');
    }
  }
  
  print('  - result: ${result.length} jobs with states');
  return result;
}
