import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/services/setup_time_service.dart';

Map<int, Map<int?, Map<int, Duration>>> buildDefaultChangeoverMatrix(
  List<MachineEntity> machines,
  Set<int> sequenceIds,
) {
  final Map<int, Map<int?, Map<int, Duration>>> matrix = {};
  for (final machine in machines) {
    if (machine.id == null) continue;
    final machineId = machine.id!;
    if (matrix.containsKey(machineId)) continue;
    final Duration baseDuration = Duration(
      minutes: (60 * machine.preparationPercentage / 100).round(),
    );
    final Map<int, Duration> defaultTargets = {
      for (final seqId in sequenceIds) seqId: baseDuration,
    };
    final Map<int?, Map<int, Duration>> machineMatrix = {
      null: Map<int, Duration>.from(defaultTargets),
    };
    for (final previous in sequenceIds) {
      machineMatrix[previous] = Map<int, Duration>.from(defaultTargets);
    }
    matrix[machineId] = machineMatrix;
  }
  return matrix;
}

Map<int, Map<int?, Map<int, Duration>>> mergeChangeoverMatrices(
  Map<int, Map<int?, Map<int, Duration>>> baseMatrix,
  Map<int, Map<int?, Map<int, Duration>>>? overrideMatrix,
) {
  if (overrideMatrix == null || overrideMatrix.isEmpty) {
    return baseMatrix;
  }

  final result = <int, Map<int?, Map<int, Duration>>>{};
  final machineIds = <int>{...baseMatrix.keys, ...overrideMatrix.keys};
  for (final machineId in machineIds) {
    final baseMachine = baseMatrix[machineId] ?? {};
    final overrideMachine = overrideMatrix[machineId] ?? {};
    final previousIds = <int?>{...baseMachine.keys, ...overrideMachine.keys};
    final mergedMachine = <int?, Map<int, Duration>>{};
    for (final previousId in previousIds) {
      final baseDurations = baseMachine[previousId] ?? {};
      final overrideDurations = overrideMachine[previousId] ?? {};
      final currentIds = <int>{
        ...baseDurations.keys,
        ...overrideDurations.keys,
      };
      final mergedDurations = <int, Duration>{};
      for (final currentId in currentIds) {
        if (overrideDurations.containsKey(currentId)) {
          mergedDurations[currentId] = overrideDurations[currentId]!;
        } else if (baseDurations.containsKey(currentId)) {
          mergedDurations[currentId] = baseDurations[currentId]!;
        }
      }
      mergedMachine[previousId] = mergedDurations;
    }
    result[machineId] = mergedMachine;
  }
  return result;
}

Future<Map<int, Map<int?, Map<int, Duration>>>> loadMergedChangeoverMatrix(
  SetupTimeService setupTimeService,
  List<MachineEntity> machines,
  Set<int> sequenceIds,
) async {
  final defaultMatrix = buildDefaultChangeoverMatrix(machines, sequenceIds);
  final dbResult = await setupTimeService.buildChangeoverMatrix();
  final dbMatrix = dbResult.fold(
    (_) => const <int, Map<int?, Map<int, Duration>>>{},
    (matrix) => matrix,
  );
  return mergeChangeoverMatrices(defaultMatrix, dbMatrix);
}
