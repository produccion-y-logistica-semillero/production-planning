import 'package:flutter/material.dart';
import 'package:production_planning/features/2_orders/presentation/pages/gantt_page.dart';

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
    // Remove explicit fixed width and make chart adaptable to zoom level
    double chartHeight = MediaQuery.of(context).size.height*0.7;
    double chartWidth = 1000; // Provide some initial large width

    return InteractiveViewer(
      boundaryMargin: const EdgeInsets.all(16.0),
      minScale: 1,
      maxScale: 5.0,  // Allow zooming in and out more freely
      child: Container(
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
      ),
    );
  }

  Widget _buildChartHeaders(double totalWidth) {
    List<Column> days = [];
    int totalDays = endDate.difference(startDate).inDays;

    //iterate over the days in range
    for (int i = 0; i <= totalDays; i++) {
      DateTime currentDate = startDate.add(Duration(days: i));

      //for this day we add the
      final dayRow =  Center(
          child: Text(
            '${currentDate.day}/${currentDate.month}',
            style: const TextStyle(fontSize: 10.0),
          ),
      );

      List<Widget> hoursRow= [];
      //iterate over the Hours in the day
      for(int i = 0; i < 24; i++){
        hoursRow.add(
          Text('${i}:00', style: TextStyle(fontSize: 4),)
        );
      }

      //adding the two rows, the day, and the row of hours to the list of columns
      days.add(
        Column(
          children: [
            dayRow,
            Row(children: hoursRow,)
          ],
        )
      );
    }


    //we return a sized box with the dynamic width depending on the days
    //and inside we have the row with all the numbers
    return SizedBox(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: days,
      ),
    );
  }
}