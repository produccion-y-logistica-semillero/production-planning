import 'package:flutter/material.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/gantt_chart.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class GanttTask {
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final Color color;

  GanttTask({
    required this.name,
    required this.startDate,
    required this.endDate,
    this.color = Colors.blue,
  });
}

// Example usage of the Gantt Chart
class GanttPage extends StatelessWidget {
  const GanttPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<GanttTask> tasks = [
      GanttTask(
        name: "Task 1",
        startDate: DateTime(2023, 9, 1, 15),
        endDate: DateTime(2023, 9, 1, 24),
        color: Colors.red,
      ),
      GanttTask(
        name: "Task 2",
        startDate: DateTime(2023, 9, 3),
        endDate: DateTime(2023, 9, 10),
        color: Colors.green,
      ),
      GanttTask(
        name: "Task 3",
        startDate: DateTime(2023, 9, 6),
        endDate: DateTime(2023, 9, 12),
        color: Colors.blue,
      ),
      GanttTask(
        name: "Task 3",
        startDate: DateTime(2023, 9, 5),
        endDate: DateTime(2023, 9, 7),
        color: Colors.blue,
      ),
      GanttTask(
        name: "Task 3",
        startDate: DateTime(2023, 9, 1),
        endDate: DateTime(2023, 9, 4),
        color: Colors.blue,
      ),
    ];

    return Scaffold(
      appBar: getAppBar(),
      body: Column(
        children: [
          GanttChart(
            tasks: tasks,
            startDate: DateTime(2023, 9, 1),
            endDate: DateTime(2023, 9, 2),
          ),
        ]
      ),
    );
  }
}