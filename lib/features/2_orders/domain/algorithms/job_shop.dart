import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class JobShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; // Working hours

  List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  // job id | due date | priority | available date

  Map<int, List<Tuple2<int, Duration>>> jobRoutes = {};
  // job id -> List of <machine id, duration>
  // Each job can have its own unique path through different machines

  List<Tuple3<int, int, Tuple2<DateTime, DateTime>>> output = [];
  // job id | machine id | <start, end time>

  JobShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.jobRoutes,
    String rule,
  ) {
    // Implement your scheduling logic based on the rule
  }
}
