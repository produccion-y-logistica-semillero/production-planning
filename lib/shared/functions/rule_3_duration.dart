Duration ruleOf3(Duration machineCapacity, Duration taskDuration){
  // Convert both durations to seconds for easier calculations
  int d1InSeconds = machineCapacity.inSeconds;
  int d2InSeconds = taskDuration.inSeconds;

  // Calculate the scaling factor where 1 hour (3600 seconds) is 1 unit
  double scaleFactor = d1InSeconds / const Duration(hours: 1).inSeconds;

  // Apply the scale factor to d2's duration
  int scaledD2InSeconds = (d2InSeconds * scaleFactor).round();

  // Return the scaled duration
  return Duration(seconds: scaledD2InSeconds);
}