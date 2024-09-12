import 'package:flutter/material.dart';
import 'package:production_planning/features/2_orders/presentation/pages/gantt_page.dart';
import 'package:provider/provider.dart';

class GanttChart extends StatefulWidget {
  final List<GanttTask> tasks;
  final DateTime startDate;
  final DateTime endDate;

  const GanttChart({
    Key? key,
    required this.tasks,
    required this.startDate,
    required this.endDate,
  }) : super(key: key);

  @override
  State<GanttChart> createState() => _GanttChartState();
}

class _GanttChartState extends State<GanttChart> {

  final ScrollController _scrollController = ScrollController();
  double _currentValue = 1;

  double _calculatePosition(DateTime date, double totalWidth) {
    int totalMinutes = widget.endDate.difference(widget.startDate).inMinutes; //total minutes of the cart
    int dayOffset = date.difference(widget.startDate).inMinutes;     //position in minutes of the passed date
    return (dayOffset / totalMinutes) * totalWidth;         //asjusted the minutes to the width size
  }

  @override
  Widget build(BuildContext context) {
    // Remove explicit fixed width and make chart adaptable to zoom level
    double chartHeight = MediaQuery.of(context).size.height*0.5;
    double chartWidth = (MediaQuery.of(context).size.width * 0.7)*_currentValue;  //the width depends on the selected by user

    return Column(
      children: [
        //slider to select the horizontal zoom
        Slider(
          value: _currentValue, 
          min: 1,
          max: 10,
          divisions: 10,
          label: _currentValue.toStringAsFixed(1),
          onChanged: (val){
            setState(() {
              _currentValue = val;
            });
          }
        ),
        //previously I used an interactive viewer for zoom, but I consider it unnecesary now
        GestureDetector(
          onHorizontalDragUpdate: (details){
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
                  _buildChartHeaders(chartWidth),
                  const SizedBox(height: 8.0),
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
                        
                        if(taskEndPosition > chartWidth) taskEndPosition = chartWidth;
                        return Positioned(
                          top: index * 50.0,
                          left: taskStartPosition,
                          child: Container(
                            width: taskEndPosition - taskStartPosition,
                            height: 40.0,
                            decoration: BoxDecoration(
                              color: task.color,
                              borderRadius: BorderRadius.circular(5)
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
    int totalDays = widget.endDate.difference(widget.startDate).inDays;

    //iterate over the days in range
    for (int i = 0; i < totalDays; i++) {
      DateTime currentDate = widget.startDate.add(Duration(days: i));

      //for this day we add the
      final dayRow =  Center(
          child: Text(
            '${currentDate.day}/${currentDate.month}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
      );

      List<Widget> hoursRow= [];
      //iterate over the Hours in the day, only if we're displaying only 1 day, for more than 1 day it doesn't look good
      if(totalDays == 1){
        for(int i = 0; i <= 24; i++){
          hoursRow.add(
            Text('${i}:00', style: TextStyle(fontSize: 12),)
          );
          hoursRow.add(SizedBox( height:10, child:  VerticalDivider(width: 2,)));
        }
      }

      //adding the two rows, the day, and the row of hours to the list of columns
      days.add(
        SizedBox(
          width: totalWidth / totalDays,
          child: Column(
            children: [
              dayRow,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: hoursRow,
              ),
              const Divider()
            ],
          ),
        )
      );
    }


    //we return a sized box with the dynamic width depending on the days
    //and inside we have the row with all the numbers
    return  Row(children: days,);
  }
}