import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';

Metrics getMetricts(List<PlanningMachineEntity> machines, List<Tuple3<DateTime, DateTime, DateTime>> jobsDates){  //(start date, end date, due date)
    machines.forEach((machine)=>machine.tasks.orderByStartDate());

    //IDLE METRIC (TIME OF MACHINES NOT BEING USED)
    Duration totalIdle = Duration.zero;
    for(final machine in machines){
      DateTime? previousEnd;
      for(final task in machine.tasks){
        if(previousEnd == null){
          previousEnd = task.endDate;
        }
        else{
          final currentIdle = task.startDate.difference(previousEnd);
          totalIdle = Duration(minutes: (totalIdle.inMinutes + currentIdle.inMinutes));
        }
      }
    }
    final Duration idle = Duration(minutes:  totalIdle.inMinutes ~/ machines.length); 

    /////////other metrics

    //avarage processing time
    final avarageProcessingMinutes = jobsDates.map((tuple)=>  tuple.value2.difference(tuple.value1))
      .reduce((previous, time)=> Duration(minutes: (previous.inMinutes + time.inMinutes)))
      .inMinutes / jobsDates.length;
    final avarageProcessingTime = Duration(minutes: avarageProcessingMinutes.toInt());

    // avarage delay
    final avarageDelayMinutes = jobsDates.map((dates)=> dates.value2.isAfter(dates.value3) ? dates.value2.difference(dates.value3) : Duration.zero)
      .reduce((previous, delay)=> Duration(minutes: (previous.inMinutes + delay.inMinutes))).inMinutes / jobsDates.length;
    final avarageDelay = Duration(minutes: avarageDelayMinutes.toInt());

    // max delay
    final maxDelay =jobsDates.map((dates)=> dates.value2.isAfter(dates.value3) ? dates.value2.difference(dates.value3) : Duration.zero)
      .reduce((previous, delay)=> delay.inMinutes > previous.inMinutes ? delay : previous);
    
    //avarage lateness (can be negative)
    final avarageLatenessMinutes = jobsDates.map((dates)=> dates.value2.difference(dates.value3))
      .reduce((previous, delay)=> Duration(minutes: (previous.inMinutes + delay.inMinutes))).inMinutes / jobsDates.length;
    final avarageLateness = Duration(minutes: avarageLatenessMinutes.toInt());

    //late jobs
    final delayedJobs = jobsDates.map((dates)=> dates.value2.isAfter(dates.value3) ? 1 : 0).reduce((p, c) => p+c);

    return Metrics(
      idle: idle, 
      totalJobs: jobsDates.length, 
      maxDelay: maxDelay, 
      avarageProcessingTime: avarageProcessingTime, 
      avarageDelayTime: avarageDelay, 
      avarageLatenessTime: avarageLateness, 
      delayedJobs: delayedJobs
    );

}

extension on List<PlanningTaskEntity>{
  void orderByStartDate(){
    for(int i = 0; i < length; i++){
      for(int j = i+1; j < length; j++){
        if(this[i].startDate.isAfter(this[j].startDate)){
          PlanningTaskEntity auxStartDate = this[i];
          this[i] = this[j];
          this[j] = auxStartDate;
        }
      }
    }
  }
}