import 'package:flutter/material.dart';
import 'package:production_planning/features/2_orders/presentation/pages/gantt_page.dart';
import 'package:provider/provider.dart';

class GanttChart extends StatefulWidget {
  final List<GanttTask> tasks;
  final DateTime startDate;
  final DateTime endDate;
  final int totalDays;

  GanttChart({
    super.key,
    required this.tasks,
    required this.startDate,
    required this.endDate,
  }): totalDays = endDate.difference(startDate).inDays;

  @override
  State<GanttChart> createState() => _GanttChartState();
}

class _GanttChartState extends State<GanttChart> {

  final ScrollController _scrollController = ScrollController();
  double _currentValue = 1;
  double hourWidth = 0;

  double _calculatePosition(DateTime date, double totalWidth) {
    int totalMinutes = widget.totalDays * 24 * 60; //total minutes of the cart
    int dayOffset = date.difference(widget.startDate).inMinutes;     //position in minutes of the passed date
    return ((dayOffset / totalMinutes) * totalWidth) + (hourWidth/2);         //asjusted the minutes to the width size, also takeninto account hour widht so it matches with the hours positions
  }

  @override
  Widget build(BuildContext context) {
    // Remove explicit fixed width and make chart adaptable to zoom level
    double chartHeight = MediaQuery.of(context).size.height*0.5;
    double chartWidth = (MediaQuery.of(context).size.width * 0.7)*_currentValue;  //the width depends on the selected by user
    hourWidth = (chartWidth/widget.totalDays)/24;


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

        //gesture detector to detect drag and scroll depending on how the user dragged
        GestureDetector(
          onHorizontalDragUpdate: (details){
            _scrollController.jumpTo(_scrollController.offset - details.delta.dx);
          },
          child: 
          //the child is a scroll view but, the controller is managed in the gesture detector, so is the gesture detector the one managing the controller
          SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  //days and hours
                  _buildChartHeaders(chartWidth),
                  const SizedBox(height: 8.0),
                  //chart
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
                        
                        if(taskEndPosition > chartWidth) taskEndPosition = chartWidth; //this is to mantaint the curvature
                        
                        //actual bar of the project and it's positioned
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
                        //actual bar of the project and it's positioned
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
    double dayWidth = totalWidth/totalDays;

    
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
      
      List<SizedBox> hoursRow= [];
      //iterate over the Hours in the day, only if we're displaying only 1 day, for more than 1 day it doesn't look good
      if(dayWidth > 800){
        int numberHours = (i < (totalDays-1)) ? 23: 24;
        for(int i = 0; i <= numberHours ; i++){
          List<Widget> column = [];
          column.add(SizedBox( height:10, child:  VerticalDivider(width: 2,)));

          column.add(
            Text('${i}:00', style: TextStyle(fontSize: 12),)
          );
          hoursRow.add(
            SizedBox(
              width: hourWidth,
              child: Column(
                children: column,
              )
            )
          );
        }
      }

      //adding the two rows, the day, and the row of hours to the list of columns
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