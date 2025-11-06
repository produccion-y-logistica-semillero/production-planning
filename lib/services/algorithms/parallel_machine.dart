import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class ParallelInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  final Map<int, Duration> durationsInMachines;

  ParallelInput(
    this.jobId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.durationsInMachines,
  );
}

class ParallelOutput {
  final int jobId;
  final int machineId;
  final DateTime startDate;
  final DateTime endDate;
  final Duration delay;
  final DateTime dueDate;

  ParallelOutput(
    this.jobId,
    this.machineId,
    this.startDate,
    this.endDate,
    this.delay,
    this.dueDate,
  );
}

class ParallelMachine {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<ParallelInput> inputJobs = [];
  Map<int, List<Tuple2<DateTime, DateTime>>> machines = {};
  List<ParallelOutput> output = [];

  ParallelMachine(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machines,
    String rule,
  ) {
    switch (rule) {
      case "SPT":
        sptRule();
        break;
      case "LPT":
        lptRule();
        break;
      case "EDD":
        eddRule();
        break;
      case "FIFO":
        fcfsRule();
        break;
      case "MINSLACK":
        minslackRule();
        break;
      case "CR":
        crRule();
        break;
      case "ATCS":
        atcRule();
        break;
      case "WSPT":
        wsptRule();
        break;
      case "SPT_ADAPTADO":
        sptaRule();
        break;
      case "EDD_ADAPTADO":
        eddaRule();
        break;
      case "FIFO_ADAPTADO":
        fifoaRule();
        break;
      case "WSPT_ADAPTADO":
        wsptaRule();
        break;
      case "LPT_ADAPTADO":
        lptaRule();
        break;
      case "MS":
        msRule();
        break;
      case "GENETICS":
        geneticsRule();
        break;


    }

  }
  void msRule() {
    _schedule((a, b) => _slack(a).compareTo(_slack(b)));
  }
  void sptRule() {
    return _schedule(
      (a, b) => _averageProcessingTime(a).compareTo(_averageProcessingTime(b)),
    );
  }

  void lptRule() {
    return _schedule(
      (a, b) => _averageProcessingTime(b).compareTo(_averageProcessingTime(a)),
    );
  }

  void eddRule() {
    return _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  void fcfsRule() {
    return _schedule((a, b) => a.availableDate.compareTo(b.availableDate));
  }

  void minslackRule() {
    return _schedule((a, b) => _slack(a).compareTo(_slack(b)));
  }

  void crRule() {
    return _schedule((a, b) => _criticalRatio(a).compareTo(_criticalRatio(b)));
  }

  void atcRule() {
    _schedule(
      (a, b) =>
          _atcPriority(b, startDate).compareTo(_atcPriority(a, startDate)),
    );
  }
  
  void wsptRule(){
    _schedule((a, b) => calculateWSPT(b).compareTo(calculateWSPT(a)));
  }
  
  void sptaRule(){
    _schedule((a,b) {
      int minTimeA = a.durationsInMachines.values.reduce((x, y) => x < y ? x : y).inMilliseconds;
      int minTimeB = b.durationsInMachines.values.reduce((x, y) => x < y ? x : y).inMilliseconds;
      return minTimeA.compareTo(minTimeB);
    }
             
    );
    
  }
  
  void eddaRule() {
    DateTime now = DateTime.now();  

    _schedule((a, b) {
      bool aAvailable = a.availableDate.isBefore(now) || a.availableDate.isAtSameMomentAs(now);
     bool bAvailable = b.availableDate.isBefore(now) || b.availableDate.isAtSameMomentAs(now);

      if (aAvailable && !bAvailable) return -1;
      if (!aAvailable && bAvailable) return 1; 
      if (!aAvailable && !bAvailable) return 0;
      return a.dueDate.compareTo(b.dueDate);
    });
  }
  
  void lptaRule(){
    DateTime now = DateTime.now();
    
    _schedule((a,b) {
      bool aAvailable = a.availableDate.isBefore(now) || a.availableDate.isAtSameMomentAs(now);
      bool bAvailable = b.availableDate.isBefore(now) || b.availableDate.isAtSameMomentAs(now);
      
      if (aAvailable && !bAvailable) return -1;
      if (!aAvailable && bAvailable) return 1; 
      if (!aAvailable && !bAvailable) return 0;
      
      return _averageProcessingTime(b).compareTo(_averageProcessingTime(a));
      });
  }
  
  void fifoaRule(){
       DateTime now = DateTime.now();
    
    _schedule((a,b) {
      bool aAvailable = a.availableDate.isBefore(now) || a.availableDate.isAtSameMomentAs(now);
      bool bAvailable = b.availableDate.isBefore(now) || b.availableDate.isAtSameMomentAs(now);
      
      if (aAvailable && !bAvailable) return -1;
      if (!aAvailable && bAvailable) return 1; 
      if (!aAvailable && !bAvailable) return 0;
      
      return a.availableDate.compareTo(b.availableDate);
      });
  }
  
  void wsptaRule() {
  DateTime now = DateTime(2025, 3, 2, 8, 0);

  _schedule((a, b) {
    bool aAvailable = a.availableDate.isBefore(now) || a.availableDate.isAtSameMomentAs(now);
    bool bAvailable = b.availableDate.isBefore(now) || b.availableDate.isAtSameMomentAs(now);

    if (aAvailable && !bAvailable) return -1;
    if (!aAvailable && bAvailable) return 1;
    if (!aAvailable && !bAvailable) return 0;

    return calculateWSPT(b).compareTo(calculateWSPT(a));
  });
}
  
  

  void _schedule(int Function(ParallelInput, ParallelInput) comparator) {
    inputJobs.sort(comparator);
    _assignJobsToMachines();
  }

  double _averageProcessingTime(ParallelInput job) {
    return job.durationsInMachines.values.fold(
          0,
          (sum, d) => sum + d.inMinutes,
        ) /
        job.durationsInMachines.length;
  }

  int _slack(ParallelInput job) {
    int remainingMinutes = job.dueDate.difference(job.availableDate).inMinutes;
    int totalProcessingTime = job.durationsInMachines.values.fold(
      0,
      (sum, d) => sum + d.inMinutes,
    );
    return remainingMinutes - totalProcessingTime;
  }

  double _criticalRatio(ParallelInput job) {
    int remainingMinutes = job.dueDate.difference(job.availableDate).inMinutes;
    int totalProcessingTime = job.durationsInMachines.values.fold(
      0,
      (sum, d) => sum + d.inMinutes,
    );
    return totalProcessingTime == 0
        ? double.infinity
        : remainingMinutes / totalProcessingTime;
  }

  double _atcPriority(ParallelInput job, DateTime currentTime) {
    double k = 2.0;
    double avgProcessingTime = _averageProcessingTime(job);

    int processingTime = job.durationsInMachines.values.fold(
      0,
      (sum, d) => sum + d.inMinutes,
    );
    int remainingTime = job.dueDate.difference(currentTime).inMinutes;

    double tardinessFactor =
        remainingTime > 0 ? remainingTime / (k * avgProcessingTime) : 0;

    return (1 / processingTime) * exp(-tardinessFactor);
  }
  
  
  double calculateWSPT(ParallelInput job) {
  int w = job.priority; // Peso
    
  int p = job.durationsInMachines.values
      .reduce((a, b) => a < b ? a : b) // Mínimo tiempo de procesamiento
      .inMilliseconds; 

  return w / p;
}
  

  void _assignJobsToMachines() {
  Map<int, DateTime> machineAvailable = {
    for (var id in machines.keys) id: startDate,
  };

  for (var job in inputJobs) {
    int jobId = job.jobId;
    DateTime dueDate = job.dueDate;
    DateTime availableDate = job.availableDate;

    int bestMachineId = -1;
    DateTime bestStartTime = DateTime.now();
    DateTime bestEndTime = DateTime.now();
    Duration bestDelay = const Duration(days: 99999);

    for (var entry in job.durationsInMachines.entries) {
      int machineId = entry.key;
      Duration processingTime = entry.value;
      
      DateTime machineStartTime =
          availableDate.isAfter(machineAvailable[machineId]!)
              ? availableDate
              : machineAvailable[machineId]!;

      machineStartTime = _adjustForWorkingSchedule(machineStartTime);
      DateTime endTime = _adjustEndTimeForWorkingSchedule(
        machineStartTime,
        processingTime,
      );
      Duration delay =
          endTime.isAfter(dueDate)
              ? endTime.difference(dueDate)
              : Duration.zero;

      if (delay < bestDelay ||
          (delay == bestDelay && endTime.isBefore(bestEndTime))) {
        bestMachineId = machineId;
        bestStartTime = machineStartTime;
        bestEndTime = endTime;
        bestDelay = delay;
      }
    }

    if (bestMachineId != -1) {
      machineAvailable[bestMachineId] = bestEndTime; // Actualiza disponibilidad
      machines[bestMachineId]?.add(Tuple2(bestStartTime, bestEndTime));
      output.add(
        ParallelOutput(
          jobId,
          bestMachineId,
          bestStartTime,
          bestEndTime,
          bestDelay,
          dueDate,
        ),
      );
    }
  }
}


  DateTime _adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour ||
        (start.hour == workingStart.hour &&
            start.minute < workingStart.minute)) {
      return DateTime(
        start.year,
        start.month,
        start.day,
        workingStart.hour,
        workingStart.minute,
      );
    } else if (start.hour > workingEnd.hour ||
        (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(
        start.year,
        start.month,
        start.day + 1,
        workingStart.hour,
        workingStart.minute,
      );
    }
    return start;
  }

  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, Duration duration) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(
      start.year,
      start.month,
      start.day,
      workingEnd.hour,
      workingEnd.minute,
    );
    DateTime endTime = start.add(duration);

    if (endTime.isAfter(endOfDay)) {
      Duration remainingTime = endTime.difference(endOfDay);
      return DateTime(
        start.year,
        start.month,
        start.day + 1,
        workingStart.hour,
        workingStart.minute,
      ).add(remainingTime);
    }
    return endTime;
  }

  void printOutput() {
    for (var out in output) {
      print(
        "Trabajo ${out.jobId} -> Máquina ${out.machineId} | Inicio: ${out.startDate} | Fin: ${out.endDate} | Retraso: ${out.delay.inMinutes} min | Vencimiento: ${out.dueDate}",
      );
    }
  }


  //ALGORITMO DE GENÉTICA Y SUS FUNCIONAS AUXILIARES -> Varias máquinas al mismo tiempo

  void geneticsRule() {
    print("EJECUTANDO ALGORITMO GENÉTICO EN PARALLEL MACHINES");

    const int populationSize = 50;
    const int generations = 100;
    const double mutationRate = 0.1;
    
    //crea la población inicial
    List<List<ParallelInput>> population = _initializePopulation(populationSize);
    List<ParallelInput> bestIndividual = [];
    //valor grande para el comienzo
    Duration bestFitness = Duration(days: 9999);

    //se repite el proceso por el numero de generaciones asignado
    for (int generation = 0; generation < generations; generation++) {
      //se evalúa cada uno de los individuos
      List<Tuple2<List<ParallelInput>, Duration>> evaluated = population.map((individual) {
        return Tuple2(individual, _evaluateFitness(individual));
      }).toList();

      //se ordena de mejor a peor según el makespan
      evaluated.sort((a, b) => a.value2.compareTo(b.value2));

      //se compara si el nuevo individuo es el mejor de las generaciones anteriores
      if (evaluated.first.value2 < bestFitness) {
        bestFitness = evaluated.first.value2;
        bestIndividual = evaluated.first.value1;
      }

      population = _generateNewPopulation(evaluated, populationSize, mutationRate);
    }

    inputJobs = bestIndividual;
    _assignJobsToMachines();
  }
  //población inicial
  List<List<ParallelInput>> _initializePopulation(int size) {
    List<List<ParallelInput>> population = [];

    for (int i = 0; i < size; i++) {
      List<ParallelInput> shuffled = List.from(inputJobs);
      shuffled.shuffle();
      population.add(shuffled);
    }

    return population;
  }
  //calcula makespan para un individuo en específico de jobs
  Duration _evaluateFitness(List<ParallelInput> jobSequence) {
    //mapa con la disponibilidad actual de cada máquina
    Map<int, DateTime> machineAvailability = {
      for (var id in machines.keys) id: startDate,
    };

    //se guarda tiempo
    DateTime latestEnd = startDate;

    //se prueba cada job en el orden del individuo
    for (var job in jobSequence) {
      DateTime bestEndTime = DateTime(9999);
      //para cada job se prueban todas las máquinas y se escoge la que termina más rápido
      for (var entry in job.durationsInMachines.entries) {
        int machineId = entry.key;
        Duration processing = entry.value;

        //se ajusta a los horarios de cada máquina, sumando al makespam si no está disponible
        DateTime available = machineAvailability[machineId]!;
        DateTime start = job.availableDate.isAfter(available) ? job.availableDate : available;
        start = _adjustForWorkingSchedule(start);
        DateTime end = _adjustEndTimeForWorkingSchedule(start, processing);

        //guarda mejor máquina para ese job
        if (end.isBefore(bestEndTime)) {
          bestEndTime = end;
        }
      }
      //actualiza makespan total
      if (bestEndTime.isAfter(latestEnd)) {
        latestEnd = bestEndTime;
      }
    }
    //devuelve el fitness de cada individuo, que es el makespan total
    return latestEnd.difference(startDate);
  }

  //crea nuevas poblaciones a partir de dos padres aleatorios
  List<List<ParallelInput>> _generateNewPopulation(
    List<Tuple2<List<ParallelInput>, Duration>> evaluated,
    int size,
    double mutationRate,
  ) {
    List<List<ParallelInput>> newPop = [];

    for (int i = 0; i < size; i++) {
      final parent1 = _selectParent(evaluated);
      final parent2 = _selectParent(evaluated);

      List<ParallelInput> child = _crossover(parent1, parent2);

      if (Random().nextDouble() < mutationRate) {
        child = _mutate(child);
      }

      newPop.add(child);
    }

    return newPop;
  }

  //elige k individuos al azar, se queda con los que menor makespan tengan
  List<ParallelInput> _selectParent(List<Tuple2<List<ParallelInput>, Duration>> evaluated) {
    int k = 5;
    final selected = List.generate(k, (_) => evaluated[Random().nextInt(evaluated.length)]);
    selected.sort((a, b) => a.value2.compareTo(b.value2));
    return selected.first.value1;
  }

  //toma ciertos jobs del individuo p1 y otros del individuo p2
    //básicamente cambia el orden de los jobs mezclando p1 y p2, sin repetir
  List<ParallelInput> _crossover(List<ParallelInput> p1, List<ParallelInput> p2) {
    final length = p1.length;
    final int point = Random().nextInt(length);
    final Set<int> jobIds = p1.sublist(0, point).map((j) => j.jobId).toSet();

    final List<ParallelInput> child = [
      ...p1.sublist(0, point),
      ...p2.where((j) => !jobIds.contains(j.jobId)),
    ];

    return child;
  }

  //intercambia el orden de dos jobs aleatoriamente
  List<ParallelInput> _mutate(List<ParallelInput> individual) {
    if (individual.length < 2) return individual;
    int i = Random().nextInt(individual.length);
    int j = Random().nextInt(individual.length);
    final temp = individual[i];
    individual[i] = individual[j];
    individual[j] = temp;
    return individual;
  }

}
