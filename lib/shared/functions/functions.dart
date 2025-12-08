import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Duration ruleOf3(Duration machineCapacity, Duration taskDuration) {
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

Duration percentageOfBaseDuration(
  double percentage, {
  Duration base = const Duration(hours: 1),
}) {
  final clampedPercentage = percentage < 0 ? 0 : percentage;
  final baseInSeconds = base.inSeconds;
  final factor = 1 + (clampedPercentage / 100);
  final totalSeconds = (baseInSeconds * factor).round();
  return Duration(seconds: totalSeconds);
}

String getDateFormat(DateTime date) {
  return DateFormat("dd/MM/yyyy HH:mm").format(date);
}

void printInfo(
  BuildContext context, {
  required String title,
  required String content,
}) {
  showDialog(
      context: context,
      builder: (c) => Dialog(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.45,
              height: MediaQuery.of(context).size.height * 0.4,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  Text(
                    content,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ));
}
