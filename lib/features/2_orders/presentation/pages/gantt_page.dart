import 'package:flutter/material.dart';

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

// Gantt Chart Widget
class GanttChart extends StatelessWidget {
  final List<GanttTask> tasks;
  final DateTime startDate;
  final DateTime endDate;

  const GanttChart({
    Key? key,
    required this.tasks,
    required this.startDate,
    required this.endDate,
  }) : super(key: key);

  double _calculatePosition(DateTime date, double totalWidth) {
    int totalDays = endDate.difference(startDate).inDays;
    int dayOffset = date.difference(startDate).inDays;
    return (dayOffset / totalDays) * totalWidth;
  }

  @override
  Widget build(BuildContext context) {
    double chartHeight = 50.0 * tasks.length;
    double chartWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeaders(chartWidth),
          const SizedBox(height: 8.0),
          Container(
            width: chartWidth,
            height: chartHeight,
            child: Stack(
              children: tasks.asMap().entries.map((entry) {
                int index = entry.key;
                GanttTask task = entry.value;
                double taskStartPosition =
                    _calculatePosition(task.startDate, chartWidth);
                double taskEndPosition =
                    _calculatePosition(task.endDate, chartWidth);

                return Positioned(
                  top: index * 50.0,
                  left: taskStartPosition,
                  child: Container(
                    width: taskEndPosition - taskStartPosition,
                    height: 40.0,
                    color: task.color,
                    child: Center(
                      child: Text(
                        task.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartHeaders(double totalWidth) {
    List<Widget> headers = [];
    int totalDays = endDate.difference(startDate).inDays;

    for (int i = 0; i <= totalDays; i++) {
      DateTime currentDate = startDate.add(Duration(days: i));
      headers.add(Expanded(
        child: Center(
          child: Text(
            '${currentDate.day}/${currentDate.month}',
            style: const TextStyle(fontSize: 10.0),
          ),
        ),
      ));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: headers,
    );
  }
}

// Example usage of the Gantt Chart
class GanttPage extends StatelessWidget {
  const GanttPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<GanttTask> tasks = [
      GanttTask(
        name: "Task 1",
        startDate: DateTime(2023, 9, 1),
        endDate: DateTime(2023, 9, 5),
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
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Gantt Chart Example"),
      ),
      body: GanttChart(
        tasks: tasks,
        startDate: DateTime(2023, 9, 1),
        endDate: DateTime(2023, 9, 12),
      ),
    );
  }
}