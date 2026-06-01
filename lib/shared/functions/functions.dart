import 'package:flutter/material.dart';
import 'package:intl/intl.dart';


Duration ruleOf3(Duration baseCapacity, Duration processingUnits) {
  // baseCapacity = machine capability in base units (e.g., 60 min for 100%)
  // processingUnits = task processing units (already a Duration, e.g., 1 hour)
  // Simply return processingUnits scaled by the ratio of baseCapacity to 1 hour
  // Formula: processingUnits * (baseCapacity / 1 hour)
  
  const Duration oneHour = Duration(hours: 1);
  double ratio = baseCapacity.inMilliseconds / oneHour.inMilliseconds;
  int scaledMilliseconds = (processingUnits.inMilliseconds * ratio).round();
  return Duration(milliseconds: scaledMilliseconds);
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

