import 'package:flutter/material.dart';
import 'package:production_planning/features/2_orders/presentation/pages/gantt_page.dart';
import 'package:intl/intl.dart';  // For formatting dates

class GanttChart extends StatefulWidget {
  final List<GanttTask> tasks;

  GanttChart({
    super.key,
    required this.tasks,
  });

  @override
  State<GanttChart> createState() => _GanttChartState(
    startDate: DateTime(2023, 9, 1),
    endDate: DateTime(2023, 9, 7),
  );
}

class _GanttChartState extends State<GanttChart> {
  final ScrollController _scrollController = ScrollController();
  double _currentValue = 1;
  double hourWidth = 0;

  DateTime startDate;
  DateTime endDate;
  int totalDays;

  _GanttChartState({
    required this.startDate,
    required this.endDate,
  }) : totalDays = endDate.difference(startDate).inDays;

  double _calculatePosition(DateTime date, double totalWidth) {
    int totalMinutes = totalDays * 24 * 60; // Total minutes of the chart
    int dayOffset = date.difference(startDate).inMinutes; // Position in minutes of the passed date
    return ((dayOffset / totalMinutes) * totalWidth) + (hourWidth / 2); // Adjust the minutes to the width size, also take into account hour width
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: startDate, end: endDate),
      firstDate: DateTime(2020), // Earliest possible date
      lastDate: DateTime(2030),  // Latest possible date
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
        totalDays = endDate.difference(startDate).inDays;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double chartHeight = MediaQuery.of(context).size.height * 0.5;
    double chartWidth = (MediaQuery.of(context).size.width * 0.7) * _currentValue; // The width depends on the user's selected zoom level
    hourWidth = (chartWidth / totalDays) / 24;

    return Column(
      children: [
        // Date range selector
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Inicio: ${DateFormat('yyyy-MM-dd').format(startDate)}'),
            const SizedBox(width: 16),
            Text('Final: ${DateFormat('yyyy-MM-dd').format(endDate)}'),
            const SizedBox(width: 16),
            Text('Numero de dias: $totalDays'),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () => _selectDateRange(context),
              child: const Text('Seleccione rango'),
            ),
          ],
        ),

        // Slider to select the horizontal zoom
        Slider(
          value: _currentValue,
          min: 1,
          max: 10,
          divisions: 10,
          label: _currentValue.toStringAsFixed(1),
          onChanged: (val) {
            setState(() {
              _currentValue = val;
            });
          },
        ),

        // Gesture detector for horizontal drag and scroll
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            _scrollController.jumpTo(_scrollController.offset - details.delta.dx);
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Days and hours headers
                  _buildChartHeaders(chartWidth),
                  const SizedBox(height: 8.0),

                  // Gantt chart
                  Container(
                    width: chartWidth,
                    height: chartHeight,
                    child: Stack(
                      children: widget.tasks.asMap().entries.map((entry) {
                        int index = entry.key;
                        GanttTask task = entry.value;
                        double taskStartPosition =
                            _calculatePosition(task.startDate, chartWidth);
                        double taskEndPosition =
                            _calculatePosition(task.endDate, chartWidth);

                        if (taskEndPosition > chartWidth) {
                          taskEndPosition = chartWidth; // Maintain the curvature
                        }

                        // Task bar on the Gantt chart
                        return Positioned(
                          top: index * 50.0,
                          left: taskStartPosition,
                          child: Container(
                            width: taskEndPosition - taskStartPosition,
                            height: 40.0,
                            decoration: BoxDecoration(
                              color: task.color,
                              borderRadius: BorderRadius.circular(5),
                            ),
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
          ),
        ),
      ],
    );
  }

  Widget _buildChartHeaders(double totalWidth) {
    List<SizedBox> days = [];
    int totalDays = endDate.difference(startDate).inDays;
    double dayWidth = totalWidth / totalDays;

    // Iterate over the days in range
    for (int i = 0; i < totalDays; i++) {
      DateTime currentDate = startDate.add(Duration(days: i));

      final dayRow = Center(
        child: Text(
          '${currentDate.day}/${currentDate.month}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

      List<SizedBox> hoursRow = [];
      // Display hours only if the day width is large enough
      if (dayWidth > 800) {
        int numberHours = (i < (totalDays - 1)) ? 23 : 24;
        for (int i = 0; i <= numberHours; i++) {
          List<Widget> column = [];
          column.add(SizedBox(height: 10, child: VerticalDivider(width: 2)));

          column.add(
            Text(
              '${i}:00',
              style: const TextStyle(fontSize: 12),
            ),
          );
          hoursRow.add(
            SizedBox(
              width: hourWidth,
              child: Column(
                children: column,
              ),
            ),
          );
        }
      }

      // Add the day and hour rows to the list of columns
      days.add(
        SizedBox(
          width: dayWidth,
          child: Column(
            children: [
              dayRow,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: hoursRow,
              ),
              const Divider(),
            ],
          ),
        ),
      );
    }

    return Row(children: days);
  }
}
