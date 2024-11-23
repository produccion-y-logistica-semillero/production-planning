import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';
import 'package:production_planning/features/2_orders/domain/algorithms/flow_shop.dart';
import 'package:production_planning/features/2_orders/domain/algorithms/parallel_machine.dart';
import 'package:production_planning/features/2_orders/domain/algorithms/single_machine.dart';
import 'package:production_planning/features/2_orders/domain/entities/metrics.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_machine_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_task_entity.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';
import 'package:production_planning/shared/functions/rule_3_duration.dart';

class ScheduleOrderUseCase implements UseCase<Tuple2<List<PlanningMachineEntity>, Metrics>?, Tuple3<int, String, String>>{

  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  ScheduleOrderUseCase({
    required this.orderRepository,
    required this.machineRepository,
  });

  @override
  Future<Either<Failure, Tuple2<List<PlanningMachineEntity>, Metrics>?>> call({required Tuple3<int, String, String> p}) async{  //tuple < orderid, rule name, enviroment name>
    return switch(p.value3){
      'SINGLE MACHINE' => Right(await singleMachineAdapter(p.value1, p.value2)),
      'PARALLEL MACHINES' => Right(await parallelMachineAdapter(p.value1, p.value2)),
      'FLOW SHOP' => Right(await flowShopAdapter(p.value1, p.value2)),
      String() => Left(EnviromentNotCorrectFailure()),
    };
  }

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> flowShopAdapter(int orderId, String rule) async {
    OrderEntity? order;
    final responseOrder = await orderRepository.getFullOrder(orderId);
    responseOrder.fold((f) {}, (or) => order = or);
    if (order == null) return null;

    // Getting all machines of the specified type
    final List<int> machinesIds = order!.orderJobs![0].sequence!.tasks!.map((t)=>t.machineTypeId).toList();
    final List<MachineEntity> machines =[];
    for(final m in machinesIds){
      final machinesSpecific = await machineRepository.getAllMachinesFromType(m);
      final machine = machinesSpecific.fold((_)=>MachineEntity.defaultMachine(), (r)=>r.first);
      machines.add(machine);
    }

    final List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
    for(final j in order!.orderJobs!){
      inputJobs.add(Tuple4(j.jobId!, j.dueDate, j.priority, j.availableDate));
    }

    final List<List<Duration>> timeMatrix = [];
    for(final j in order!.orderJobs!){
      final List<Duration> jobDurations = [];
      int i = 0;
      for(final t in j.sequence!.tasks!){
        jobDurations.add(ruleOf3(machines[i].processingTime, t.processingUnits));
        i++;
      }
      timeMatrix.add(jobDurations);
    }

    final output = FlowShop(
      order!.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      timeMatrix,
      rule,
    ).output;

    final List<PlanningMachineEntity> planningMachines = [];
    for(final m in machines){
      planningMachines.add(PlanningMachineEntity(m.id!, m.name, []));
    }

    final List<DateTime> endDateJobs = [];
    for(final jr in output){
      int i = 0;
      DateTime? aux;
      for(final plan in jr.value2){
        if(aux == null || aux.isBefore(plan.value2)){
          aux = plan.value2;
        }
        planningMachines[i].tasks.add(
          PlanningTaskEntity(
            sequenceId: order!.orderJobs!.where((j)=>j.jobId == jr.value1).first.sequence!.id!, 
            sequenceName: order!.orderJobs!.where((j)=>j.jobId == jr.value1).first.sequence!.name!, 
            taskId: order!.orderJobs!.where((j)=>j.jobId == jr.value1).first.sequence!.tasks![i].id!, 
            numberProcess: i+1, 
            startDate: plan.value1, 
            endDate: plan.value2, 
            retarded: false, 
            orderId: orderId, 
            jobId: jr.value1
            )
          );
        i++;
      }
      endDateJobs.add(aux!);
    }

    final List<Tuple3<DateTime, DateTime, DateTime>> jobsDates = [];
    int i = 0;
    for(final j in order!.orderJobs!){
      jobsDates.add(Tuple3(j.availableDate, endDateJobs[i], j.dueDate));
      i++;
    }
    final metrics = getMetricts(
      planningMachines,
      jobsDates,
    );

    return Tuple2(planningMachines, metrics);
  }




  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> parallelMachineAdapter(int orderId, String rule) async {
    OrderEntity? order;
    final responseOrder = await orderRepository.getFullOrder(orderId);
    responseOrder.fold((f) {}, (or) => order = or);
    if (order == null) return null;

    int machineTypeid = order!.orderJobs![0].sequence!.tasks![0].machineTypeId;
    List<MachineEntity> machineEntities = [];
    final responseMachines = await machineRepository.getAllMachinesFromType(machineTypeid);
    responseMachines.fold((f) {}, (m) => machineEntities = m);
    if (machineEntities.isEmpty) return null;

    String machineTypeName = "";
    final responseTypeMachine = await machineRepository.getMachineTypeName(machineTypeid);
    responseTypeMachine.fold((f) {}, (name) => machineTypeName = name);

    final List<Tuple5<int, DateTime, int, DateTime, List<Duration>>> inputJobs = order!.orderJobs!
        .map((job) => Tuple5<int, DateTime, int, DateTime, List<Duration>>(
            job.jobId!,
            job.dueDate,
            job.priority,
            job.availableDate,
            job.sequence!.tasks!.map((task) => task.processingUnits).toList()))
        .toList();

    final List<Tuple2<int, List<Tuple2<DateTime, DateTime>>>> machines = machineEntities
        .map((machine) => Tuple2<int, List<Tuple2<DateTime, DateTime>>>(machine.id!, []))
        .toList();

    final output = ParallelMachine(
      order!.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machines,
      rule,
    ).output;

    final Map<int, List<PlanningTaskEntity>> machineTasksMap = {};

    for (var out in output) {
      final job = order!.orderJobs!.firstWhere((job) => job.jobId == out.value1);
      final task = PlanningTaskEntity(
        sequenceId: job.sequence!.id!,
        sequenceName: job.sequence!.name,
        taskId: job.sequence!.tasks![0].id!,
        numberProcess: 1,
        startDate: out.value3,
        endDate: out.value4,
        retarded: out.value5 > Duration.zero,
        jobId: job.jobId!,
        orderId: orderId,
      );

      if (!machineTasksMap.containsKey(out.value2)) {
        machineTasksMap[out.value2] = [];
      }
      machineTasksMap[out.value2]!.add(task);
    }
    machineEntities.forEach((m)=>print(m.id));
    final List<PlanningMachineEntity> machinesResult = machineTasksMap.entries
        .map((entry) => PlanningMachineEntity(
            entry.key,
            machineEntities.where((m)=>m.id == entry.key).first.name,
            entry.value,
          ))
        .toList();

    final metrics = getMetricts(
      machinesResult,
      output.map((out) => Tuple3(out.value3, out.value4, out.value6)).toList(),
    );

    return Tuple2(machinesResult, metrics);
  }


  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> singleMachineAdapter(int orderId, String rule) async{
    OrderEntity? order;
    final responseOrder = await orderRepository.getFullOrder(orderId);
    responseOrder.fold((f){}, (or)=>order = or);
    if(order == null) return null;

    MachineEntity? machineEntity;
    int machineTypeid = order!.orderJobs![0].sequence!.tasks![0].machineTypeId;
    final responseMachine = await machineRepository.getAllMachinesFromType(machineTypeid);
    responseMachine.fold((f){}, (m)=> machineEntity = m[0]);
    if(machineEntity == null) return null;

    String machineTypeName = "";
    final responseTypeMachine = await machineRepository.getMachineTypeName(machineTypeid);
    responseTypeMachine.fold((f){}, (name)=>machineTypeName = name);

    final List<Tuple5<int, Duration, DateTime, int, DateTime>> input =  order!.orderJobs!
      .map((job)=> Tuple5<int, Duration, DateTime, int, DateTime>(
          job.jobId!,
          ruleOf3(
            machineEntity!.processingTime,
            job.sequence!.tasks![0].processingUnits 
          ),
          job.dueDate,
          job.priority,
          job.availableDate
        )
      ).toList();

    final output = SingleMachine(
      0,
      order!.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      input,
      rule
    ).output;
    
    final tasks = output.map((out)=>PlanningTaskEntity(
        sequenceId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.id!,
        sequenceName: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.name,
        taskId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.tasks![0].id!,
        numberProcess:  1,    //to change later depending on amount of a sequence
        startDate: out.value3,
        endDate: out.value4,
        retarded: !out.value4.isBefore(out.value5),
        jobId: out.value1,
        orderId: orderId,
      )
    ).toList();

    final machinesResult = [
      PlanningMachineEntity(
        machineEntity!.id!,
        machineTypeName,
        tasks
      )
    ];

    final metrics = getMetricts(
      machinesResult, 
      output.map(
        (out)=> Tuple3(out.value3, out.value4,out.value5)
      )
      .toList()
    );

    return Tuple2(machinesResult, metrics);
  }


 


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