import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_machine_entity.dart';
import 'package:production_planning/features/2_orders/presentation/pages/gantt_page.dart';
import 'package:intl/intl.dart';  // For formatting dates

class GanttChart extends StatefulWidget {
  final List<PlanningMachineEntity> machines;

  GanttChart({
    super.key,
    required this.machines,
  });

  @override
  State<GanttChart> createState() => _GanttChartState(
    startDate: DateTime(2023, 9, 1),
    endDate: DateTime(2023, 9, 7),
  );
}

class _GanttChartState extends State<GanttChart> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _vertical2ScrollController = ScrollController();
  double _currentHorizontalValue = 1;
  double _currentVerticalValue = 1;
  double hourWidth = 0;
  Map<String, Color> processColor = {};

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
    double chartHeight = MediaQuery.of(context).size.height * 0.7;
    double chartWidth = (MediaQuery.of(context).size.width * 0.7) * _currentHorizontalValue; // The width depends on the user's selected zoom level
    hourWidth = (chartWidth / totalDays) / 24;
    double stackHeight = ((widget.machines.length+1) * (45.0*_currentVerticalValue));
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
          value: _currentHorizontalValue,
          min: 1,
          max: 10,
          divisions: 40,
          label: _currentHorizontalValue.toStringAsFixed(1),
          onChanged: (val) {
            setState(() {
              _currentHorizontalValue = val;
            });
          },
        ),
        Row(
          children: [
            SizedBox(
              height: chartHeight + 8.0,
              child: RotatedBox(
                quarterTurns: 1,
                child: Slider(
                  value: _currentVerticalValue, 
                  min: 1,
                  max: 10,
                  divisions: 40,
                  label: _currentVerticalValue.toStringAsFixed(1),
                  onChanged: (val){
                    setState(() {
                      _currentVerticalValue = val;
                    });
                  }
                ),
              ),
            ),
            // Gesture detector for horizontal drag and scroll
            Container(
              height: chartHeight,
              width: 200,
              margin: EdgeInsets.only(top: 70),
              child: SingleChildScrollView(
                controller: _vertical2ScrollController,
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.vertical,
                child: SizedBox(
                  height: stackHeight,
                  width: 100,
                  child: Stack(
                    children: getMachines(widget.machines, context),
                  ),
                )
              ),
            ),
            Container(
              width: MediaQuery.of(context).size.width*0.67,
              margin: EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(width: 4)
              ),
              child: GestureDetector(
                onPanUpdate: (details) {
                  _horizontalScrollController.jumpTo(_horizontalScrollController.offset - details.delta.dx);
                  _verticalScrollController.jumpTo(_verticalScrollController.offset - details.delta.dy);
                  _vertical2ScrollController.jumpTo(_vertical2ScrollController.offset - details.delta.dy);
                },
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    width: chartWidth+50,
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Days and hours headers
                        _buildChartHeaders(chartWidth),
                        const SizedBox(height: 1.0),
                  
                        // Gantt chart
                        Container(
                          height: chartHeight,
                          child: SingleChildScrollView(
                            controller: _verticalScrollController,
                            physics: const NeverScrollableScrollPhysics(),
                            scrollDirection: Axis.vertical ,
                            child: SizedBox(
                              height: stackHeight,
                              width: chartWidth,
                              child: Stack(
                                children: getTasks(widget.machines, chartWidth),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        )
      ],
    );
  }

  List<Widget> getMachines(List<PlanningMachineEntity> machines, BuildContext context){
    List<Widget> machineWidgets = [];

    for(int index = 0; index < machines.length; index++)
    {
      machineWidgets.add(
        Positioned(
          left: 5,
          top: (index * (40.0*_currentVerticalValue)) + (5*index),
          child: Container(
            height: 40.0 * _currentVerticalValue,
            width: 190,
            padding: EdgeInsets.all( 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(machines[index].machineName, style: TextStyle(color: Colors.white),),
          )
        )
      );
    }

    return machineWidgets;
  }

  List<Widget> getTasks(List<PlanningMachineEntity> machines, double chartWidth){
    List<Widget> ganttItems = [];

    for(int index = 0; index < machines.length; index++){
      for(final task in machines[index].tasks){
        double taskStartPosition = _calculatePosition(task.startDate, chartWidth);
        double taskEndPosition = _calculatePosition(task.endDate, chartWidth);
        if (taskEndPosition > chartWidth) {
          taskEndPosition = chartWidth; // Maintain the curvature
        }

        if(!processColor.containsKey('${task.sequenceId}-${task.numberProcess}')){
          final random = Random();
          processColor['${task.sequenceId}-${task.numberProcess}'] = Color.fromARGB(
            255, // Alpha value (opacity)
            random.nextInt(256), // Red value
            random.nextInt(256), // Green value
            random.nextInt(256), // Blue value
          );
        }
        final Color taskColor = processColor['${task.sequenceId}-${task.numberProcess}']!;
        // Task bar on the Gantt chart
        final item = Positioned(
          top: (index * (40.0*_currentVerticalValue)) + (5*index),
          left: taskStartPosition,
          child: Container(
            width: taskEndPosition - taskStartPosition,
            height: 40.0 * _currentVerticalValue,
            decoration: BoxDecoration(
              color: taskColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Center(
              child: Text(
                '${task.sequenceName} ${task.numberProcess}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
        ganttItems.add(item);
      }
    }
    return ganttItems;
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
        int numberHours = (i < (totalDays - 1)) ? 23 : 24;
        for (int i = 0; i <= numberHours; i++) {
          List<Widget> column = [];
          double height =  dayWidth > 800 ? 10: 15;
          if(i == 0) height = 30;
          column.add(SizedBox(height: height, child: VerticalDivider(thickness: i == 0?4: 1, width: 2)));
          if (dayWidth > 800) {
            if(i != 0) column.add(
              Text(
                '${i}:00',
                style: const TextStyle(fontSize: 12),
              ),
            );
          }
          hoursRow.add(
            SizedBox(
              width: hourWidth,
              child: Column(
                children: column,
              ),
            ),
          );
        }

      // Add the day and hour rows to the list of columns
      days.add(
        SizedBox(
          width: dayWidth,
          child: SizedBox(
            height: 70,
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
        ),
      );
    }

    return Row(children: days);
  }
}
