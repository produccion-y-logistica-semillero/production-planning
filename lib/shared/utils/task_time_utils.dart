import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_times.dart';
import 'package:production_planning/entities/task_entity.dart';

/// Returns the explicit Duration for [job]-[taskId]-[machine] when available.
/// Tries the following fallbacks in order:
/// 1. inner[machine.id]
/// 2. if inner has exactly one entry, return that value (orders saved before
///    the job form stored one entry per machine of the station)
/// 3. null if nothing found
///
/// There used to be a lookup by `machine.machineTypeId` between the two. The
/// map is keyed by machine id, so that lookup compared ids of two different
/// tables and could return another machine's time.
MachineTimes? getExplicitMachineTimes(
    JobEntity job, int taskId, MachineEntity machine) {
  if (job.taskMachineTimes == null) return null;
  final inner = job.taskMachineTimes![taskId];
  if (inner == null || inner.isEmpty) return null;

  // 1. Try machine.id
  if (machine.id != null && inner.containsKey(machine.id)) {
    return inner[machine.id];
  }

  // 2. If only one mapping exists, return it (legacy rows)
  if (inner.length == 1) {
    return inner.values.first;
  }

  return null;
}

/// Minutes [task] takes on [machine] before the user types anything: the
/// task's own time scaled by the machine's processing percentage (100, or a
/// non-positive value, means "identical machine": the time as is).
int nominalTaskMinutesOn(TaskEntity task, MachineEntity machine) {
  final int base = task.processingUnits.inMinutes;
  final double pct = machine.processingPercentage;
  if (pct == 100 || pct <= 0) return base;
  return (base * pct / 100).round();
}

/// The per-machine times of ONE task of a job, as the job form keeps them:
/// one entry for EVERY machine of the task's station, keyed by machine id.
///
/// The form used to keep a single entry per task (the "selected" machine),
/// so typing a time for a second machine of the station erased the first
/// one, and the scheduler then applied that lone entry to every machine.
///
/// [saved] is what the job already has for this task (null for a new job).
/// A saved entry always wins. A machine with no saved entry gets:
///  * the single saved value, when [saved] has exactly one entry — orders
///    stored in the old one-entry format were scheduled with that value on
///    every machine, and reopening one must not change its schedule;
///  * [nominalTaskMinutesOn] otherwise.
/// Entries of machines that are no longer in [stationMachines] are dropped.
Map<int, Map<String, int>> seedTaskMachineMinutes({
  required TaskEntity task,
  required List<MachineEntity> stationMachines,
  Map<int, Map<String, int>>? saved,
}) {
  final int? legacyMinutes = (saved != null && saved.length == 1)
      ? saved.values.first['processing']
      : null;

  final result = <int, Map<String, int>>{};
  for (final machine in stationMachines) {
    final int? id = machine.id;
    if (id == null) continue;
    final int minutes = saved?[id]?['processing'] ??
        legacyMinutes ??
        nominalTaskMinutesOn(task, machine);
    result[id] = {
      'processing': minutes,
      'preparation': 0, // setup comes from the setup matrix
      'rest': 0, // rest is the machine's own policy
    };
  }
  return result;
}

/// Returns the explicit processing Duration for [job]-[taskId]-[machine] when available.
/// This is a convenience function that extracts only the processing time from MachineTimes.
Duration? getExplicitProcessingDuration(
    JobEntity job, int taskId, MachineEntity machine) {
  final machineTime = getExplicitMachineTimes(job, taskId, machine);
  return machineTime?.processing;
}

/// Whether [job]'s processing of [task] on [machineId] may be split by a
/// work-shift boundary, the continuous-use rest cap, or a maintenance
/// window. [job.preemptionMatrix] (per job, per machine — 1 = interruptible)
/// takes priority when it has an entry for [machineId]; otherwise falls back
/// to [task.allowPreemption] (the task's own default, set when the sequence
/// was created).
bool resolveInterruptible(JobEntity job, TaskEntity task, int machineId) {
  final override = job.preemptionMatrix?[machineId];
  if (override != null) return override != 0;
  return task.allowPreemption;
}

/// Longest "continuous processing before a rest" that still means anything:
/// the scheduling horizon (366 days, see PreemptionEngine.maxHorizonDays), in
/// minutes. A cap at or beyond it can never bind.
const int maxContinuousCapacityMinutes = 366 * 24 * 60;

/// The automatic-rest policy of [machine] as every algorithm expects it:
/// minutes of continuous processing before a rest, and how long the rest is.
///
/// "No rest" — the machine form's "No aplica descanso automático" — comes
/// back as capacity 0 and a zero rest, which the preemption engine treats as
/// no cap at all. That is the case when the capacity is 0 or negative, when
/// the rest is 0 or negative, or when the capacity is at or beyond the
/// scheduling horizon (a "very large value" typed to mean the same thing —
/// kept out of `Duration(minutes:)`, which overflows for absurd inputs).
///
/// Every adapter reads the policy through here. They used to disagree: Job
/// Shop and Flexible Job Shop turned a zero rest into one hour, the others
/// passed it on and the engine then inserted a one-minute pause at each cap.
({int capacityMinutes, Duration rest}) machineRestPolicy(
    MachineEntity machine) {
  final int capacity = machine.continueCapacity;
  // rest_percentage stores the rest as a percentage of one hour.
  final int restMinutes = (60 * machine.restPercentage / 100).round();
  if (capacity <= 0 ||
      capacity >= maxContinuousCapacityMinutes ||
      restMinutes <= 0) {
    return (capacityMinutes: 0, rest: Duration.zero);
  }
  return (capacityMinutes: capacity, rest: Duration(minutes: restMinutes));
}

String _normalizeMachineName(String machineName) {
  return machineName.trim().toLowerCase();
}

/// [machines] ordered by id (machines without one last), so "the first
/// sibling with its own entry" is always the same machine.
List<MachineEntity> _byId(List<MachineEntity> machines) =>
    List<MachineEntity>.from(machines)
      ..sort((a, b) => (a.id ?? 1 << 30).compareTo(b.id ?? 1 << 30));

/// Where a machine's setup matrix (or initial state) comes from — the same
/// rule [buildMachineStateSetupMatrix] and [resolveMachineInitialStates]
/// apply, exposed for the order screen so it can show it to the user.
///
/// [stationMachines] are every machine of ONE station (same machine type).
/// [namesWithOwnEntry] are the machine names that have their own entry.
/// Returns, per machine name of the station: the machine's own name when it
/// has its own entry, the name of the sibling it inherits from otherwise
/// (the lowest-id sibling with its own entry), or null when no machine of
/// the station has one.
Map<String, String?> stationDefaultSource(
  List<MachineEntity> stationMachines,
  Set<String> namesWithOwnEntry,
) {
  final own = {for (final n in namesWithOwnEntry) _normalizeMachineName(n)};
  String? fallback;
  for (final machine in _byId(stationMachines)) {
    if (own.contains(_normalizeMachineName(machine.name))) {
      fallback = machine.name;
      break;
    }
  }
  return {
    for (final machine in stationMachines)
      machine.name: own.contains(_normalizeMachineName(machine.name))
          ? machine.name
          : fallback,
  };
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

  // A machine of a station with no matrix of its own inherits the matrix
  // registered for another machine of the SAME machine type — the station's
  // default — instead of always getting zero setup. Only machines that
  // matched nothing above are filled this way; an explicit match always
  // wins. When several siblings have their own matrix, the one with the
  // LOWEST machine id is the default (see [stationDefaultSource]), so the
  // result does not depend on the order machines were loaded in.
  final Map<int, Map<String, Map<String, int>>> defaultByType = {};
  for (final machine in _byId(machines)) {
    final typeId = machine.machineTypeId;
    if (machine.id == null || typeId == null) continue;
    final own = result[machine.id!];
    if (own != null) {
      defaultByType.putIfAbsent(typeId, () => own);
    }
  }
  for (final machine in machines) {
    if (machine.id == null || result.containsKey(machine.id)) continue;
    final typeId = machine.machineTypeId;
    final fallback = typeId == null ? null : defaultByType[typeId];
    if (fallback != null) {
      print('  - machine "${machine.name}" (id=${machine.id}) inherits the '
          'setup matrix of another machine of type $typeId');
      result[machine.id!] = fallback;
    }
  }

  print('  - result: ${result.isEmpty ? "EMPTY (no matches)" : "${result.length} machines matched"}');
  return result.isEmpty ? null : result;
}

/// Converts an order-level machine-initial-state map (keyed by machine
/// name, as saved with the order) into one keyed by machine id — the shape
/// every scheduling algorithm's `initialMachineState` parameter expects.
///
/// A machine with no entry of its own inherits the state registered for
/// another machine of the SAME machine type, same fallback as
/// [buildMachineStateSetupMatrix].
Map<int, String> resolveMachineInitialStates(
  List<MachineEntity> machines,
  Map<String, String>? orderMachineInitialStates,
) {
  if (orderMachineInitialStates == null || orderMachineInitialStates.isEmpty) {
    return const {};
  }

  final normalized = <String, String>{
    for (final entry in orderMachineInitialStates.entries)
      _normalizeMachineName(entry.key): entry.value,
  };

  final result = <int, String>{};
  for (final machine in machines) {
    if (machine.id == null) continue;
    final state = normalized[_normalizeMachineName(machine.name)];
    if (state != null) result[machine.id!] = state;
  }

  final Map<int, String> defaultByType = {};
  for (final machine in _byId(machines)) {
    final typeId = machine.machineTypeId;
    if (machine.id == null || typeId == null) continue;
    final own = result[machine.id!];
    if (own != null) defaultByType.putIfAbsent(typeId, () => own);
  }
  for (final machine in machines) {
    if (machine.id == null || result.containsKey(machine.id)) continue;
    final typeId = machine.machineTypeId;
    final fallback = typeId == null ? null : defaultByType[typeId];
    if (fallback != null) result[machine.id!] = fallback;
  }

  return result;
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
