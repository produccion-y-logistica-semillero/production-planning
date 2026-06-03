/// Resolves changeover / setup duration between jobs on a machine.
Duration resolveSetupDuration({
  required int machineId,
  required int currentSequenceId,
  required int? previousSequenceId,
  required int? currentJobId,
  required int? previousJobId,
  required Map<int, Map<int?, Map<int, Duration>>> changeoverMatrix,
  Map<int, Map<String, Map<String, int>>>? stateSetupMatrix,
  Map<int, Map<int, String>>? jobStates,
}) {
  if (previousJobId != null &&
      previousJobId > 0 &&
      currentJobId != null &&
      stateSetupMatrix != null &&
      jobStates != null) {
    final machineStates = stateSetupMatrix[machineId];
    if (machineStates != null) {
      final previousState = jobStates[previousJobId]?[machineId];
      final currentState = jobStates[currentJobId]?[machineId];
      if (previousState != null && currentState != null) {
        final setupMinutes = machineStates[previousState]?[currentState];
        if (setupMinutes != null) {
          return Duration(minutes: setupMinutes);
        }
      }
    }
  }

  final machineMatrix = changeoverMatrix[machineId];
  if (machineMatrix == null) return Duration.zero;

  if (previousSequenceId != null) {
    final previousDurations = machineMatrix[previousSequenceId];
    if (previousDurations != null &&
        previousDurations.containsKey(currentSequenceId)) {
      return previousDurations[currentSequenceId]!;
    }
  }

  final defaultDurations = machineMatrix[null];
  if (defaultDurations != null &&
      defaultDurations.containsKey(currentSequenceId)) {
    return defaultDurations[currentSequenceId]!;
  }

  return Duration.zero;
}
