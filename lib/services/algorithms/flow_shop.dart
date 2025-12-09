import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class FlowShopInput {
  final int jobId;

  final int sequenceId;

  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  //this list has the order of the tasks, it has a tuple of 2 <task id, machine id>
  final List<Tuple2<int, int>> taskSequence;
  //in this map we have the durations, the id is the task id, and the duration is how long it takes (since we know there's only one machine, and we already have that time)
  final Map<int, Duration> taskTimesInMachines;
  FlowShopInput(

    this.jobId,
    this.sequenceId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.taskSequence,
    this.taskTimesInMachines,
  );

}

class FlowShopOutput {
  final int jobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  //the output, the map has the key the machine id, the value is a tuple of <task id, range start to end time>
  final Map<int, Tuple2<int, Range>> machinesScheduling;
  FlowShopOutput(

    this.jobId,
    this.startDate,
    this.dueDate,
    this.endTime,
    this.machinesScheduling,
  );

}

class FlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17

  //List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  List<FlowShopInput> inputJobs = [];
  //List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  //the input comes like a table of type
  //  job id   |     due date        |       priority  | Available date
  //  1         |   2024/8/30/6:00    |         1       | 2024/8/30/6:00
  //  2         |   2024/8/30/6:00    |         3       | 2024/8/30/6:00
  //  3         |   2024/8/30/6:00    |         2       | 2024/8/30/6:00

  //this is to help in the algorithm, here we check until what date the machine of this ID is not available
  Map<int, DateTime> machinesAvailability = {};
  //List<List<Duration>> timeMatrix =[]; //matrix of time it takes the task in each machine type
  //  The first list (rows) are the indexes of jobs, and the inside list (columns) are the times in each machine type
  //  the indexes in these lists (matrix) point to the same indexes in the list of inputJobs and machineId's
  //          :   0   |   1   |   2   |   3   |
  //      0     10:25 | 01:30 | 02:45 | 00:45 |
  //      1     08:25 | 00:30 | 02:50 | 00:12 |

  List<FlowShopOutput> output = [];
  //List<Tuple3<int, List<Tuple2<DateTime, DateTime>>, DateTime>> output = [];
  //         |   Machine index 0   |   Machine index 1  |  Machine index 2    ....| DUE DATE
  // job 1   |   <10:00, 12:00>    |   <14:00, 17:00>   |    <18:00, 20:30>   ....|
  // job 2   |   <12:00, 13:45>    |   <17:00, 18:00>   |    <20:30, 21:30>   ....|


  final Map<int, Map<int?, Map<int, Duration>>> changeoverMatrix;
  final Map<int, int?> _machineLastSequence = {};

  FlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule, {
    Map<int, Map<int?, Map<int, Duration>>>? changeoverMatrix,
  }) : changeoverMatrix = changeoverMatrix ?? {} {
    _initializeMachineLastSequence();

    switch (rule) {
      case "EDD":
        eddRule();
        break;
      case "SPT":
        sptRule();
        break;
      case "LPT":
        lptRule();
        break;
      case "FIFO":
        fifoRule();
        break;
      case "WSPT":
        wsptRule();
        break;
      case "EDD_ADAPTADO":
        eddaRule();
        break;
      case "SPT_ADAPTADO":
        sptaRule();
        break;
      case "LPT_ADAPTADO":
        lptaRule();
        break;
      case "FIFO_ADAPTADO":
        fifoaRule();
        break;
      case "WSPT_ADAPTADO":
        wsptaRule();
        break;
      case "JOHNSON":
        _applyJohnsonRule(inputJobs);
        break;
      case "CDS":
        cdsAlgorithm();
        break;
      case "MINSLACK":
        msRule();
        break;
      case "CR":
        crRule();
        break;
      case "ATCS":
        atcRule();
        break;
      case "GENETICS":
        scheduleGeneticAlgorithm();
        break;

    }
  }

  void eddRule() => _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  void sptRule() => _schedule(
        (a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)),

  );
  void lptRule() => _schedule(
        (a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)),
  );
  void fifoRule() =>
      _schedule((a, b) => a.availableDate.compareTo(b.availableDate));
  void wsptRule() => _schedule((a, b) {
    double wsptA = a.priority / _totalProcessingTime(a);
    double wsptB = b.priority / _totalProcessingTime(b);
    return wsptB.compareTo(wsptA);
  });
  void eddaRule() => dynamicRule((a, b) => a.dueDate.compareTo(b.dueDate));
  void sptaRule() => dynamicRule(
        (a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)),
  );
  void lptaRule() => dynamicRule(
        (a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)),
  );
  void fifoaRule() =>
      dynamicRule((a, b) => a.availableDate.compareTo(b.availableDate));
  void wsptaRule() => dynamicRule((a, b) {
    double wsptA = a.priority / _totalProcessingTime(a);
    double wsptB = b.priority / _totalProcessingTime(b);
    return wsptB.compareTo(wsptA);
  });


  void msRule() {
    int totalProcessingTimeAccumulated = 0;
    List<FlowShopInput> remainingJobs = List.from(inputJobs);

    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort((a, b) {
        int slackA = _calculateSlack(a, totalProcessingTimeAccumulated);
        int slackB = _calculateSlack(b, totalProcessingTimeAccumulated);
        return slackA.compareTo(slackB);
      });

      FlowShopInput selectedJob = remainingJobs.first;
      _assignJobToMachines(selectedJob);
      // Actualizamos el tiempo total de procesamiento acumulado con el trabajo seleccionado
      totalProcessingTimeAccumulated += _totalProcessingTime(selectedJob);
      remainingJobs.remove(selectedJob);
    }
  }

  void crRule() {
    int totalProcessingTimeAccumulated = 0;
    List<FlowShopInput> remainingJobs = List.from(inputJobs);

    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort((a, b) {
        double crA = _calculateCR(a, totalProcessingTimeAccumulated);
        double crB = _calculateCR(b, totalProcessingTimeAccumulated);
        return crA.compareTo(crB);
      });

      FlowShopInput selectedJob = remainingJobs.first;
      _assignJobToMachines(selectedJob);
      totalProcessingTimeAccumulated += _totalProcessingTime(selectedJob);
      remainingJobs.remove(selectedJob);
    }
  }

  void atcRule() {
    DateTime currentTime = startDate;
    List<FlowShopInput> remainingJobs = List.from(inputJobs);
    output.clear();
    int elapsedTime = 0;
    double K = 3.0;

    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort(
            (a, b) => _calculateATCPriority(

          b,
          currentTime,
          elapsedTime,
          K,
        ).compareTo(_calculateATCPriority(a, currentTime, elapsedTime, K)),
      );
      FlowShopInput selectedJob = remainingJobs.removeAt(0);
      _assignJobToMachines(selectedJob);
      elapsedTime += _totalProcessingTime(selectedJob);
      currentTime = output.last.endTime;
    }
  }

  double _calculateATCPriority(
HEAD<<<<<<< 
      FlowShopInput job,
      DateTime currentTime,
      int elapsedTime,
      double k,
      ) {

    int processingTime = _totalProcessingTime(job);
    double avgProcessingTime = processingTime / job.taskSequence.length;
    double timeDiff = job.dueDate.difference(currentTime).inMinutes.toDouble();
    double slackTime = (timeDiff - processingTime - elapsedTime).clamp(
      0,
      double.infinity,
    );
    double expFactor = exp(-slackTime / (k * avgProcessingTime));
    return (job.priority / processingTime) * expFactor;
  }

  void _schedule(int Function(FlowShopInput, FlowShopInput) comparator) {
    inputJobs.sort(comparator);
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void _assignJobToMachines(FlowShopInput job) {
    DateTime jobStartTime = job.availableDate;
    Map<int, Tuple2<int, Range>> scheduling = {};

    for (var task in job.taskSequence) {
      int taskId = task.value1;
      int machineId = task.value2;
      Duration duration = job.taskTimesInMachines[taskId]!;

      DateTime machineAvailable = machinesAvailability[machineId] ?? startDate;

      DateTime startTime =
      jobStartTime.isAfter(machineAvailable)
          ? jobStartTime
          : machineAvailable;
      startTime = _adjustForWorkingSchedule(startTime);
      DateTime endTime = startTime.add(duration);
      endTime = _adjustEndTimeForWorkingSchedule(startTime, endTime);

      scheduling[machineId] = Tuple2(taskId, Range(startTime, endTime));
      machinesAvailability[machineId] = endTime;

      jobStartTime = endTime;
    }

    output.add(
      FlowShopOutput(
        job.jobId,
        job.availableDate,
        job.dueDate,
        jobStartTime,
        scheduling,
      ),
    );
  }


  int _totalProcessingTime(FlowShopInput job) {
    return job.taskTimesInMachines.values.fold(
      0,
          (sum, duration) => sum + duration.inMinutes,

    );
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
  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(
      start.year,
      start.month,
      start.day,
      workingEnd.hour,
      workingEnd.minute,
    );

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(
        start.year,
        start.month,
        start.day + 1,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      ).add(remainingTime);
    }
    return end;

  }

  void dynamicRule(int Function(FlowShopInput, FlowShopInput) comparator) {
    List<FlowShopInput> remainingJobs = List.from(inputJobs);
    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort(comparator);
      FlowShopInput selectedJob = remainingJobs.removeAt(0);
      _assignJobToMachines(selectedJob);
    }
  }

  int _calculateSlack(FlowShopInput job, int accumulatedTime) {
    int totalProcessingTime = _totalProcessingTime(job);

    // Calculamos el slack: max(d_j - p_j - t, 0)
    DateTime currentTime = DateTime.now();
    int slack =
        job.dueDate.difference(currentTime).inMinutes -
            totalProcessingTime -
            accumulatedTime;

    // Si el slack es negativo, lo consideramos como 0
    return slack < 0 ? 0 : slack;
  }

  double _calculateCR(FlowShopInput job, int accumulatedTime) {
    int remainingTime = max(
      job.dueDate.difference(DateTime.now()).inMinutes - accumulatedTime,
      0,
    );
    int processingTime = _totalProcessingTime(job);
    return processingTime > 0
        ? remainingTime / processingTime
        : double.infinity;
  }

  void cdsAlgorithm() {
    if (inputJobs.isEmpty) return;

    int numMachines = inputJobs.first.taskSequence.length;

    // Si solo hay 2 máquinas, aplicamos directamente Johnson
    if (numMachines == 2) {
      _applyJohnsonRule(inputJobs);
      return;
    }

    // Si hay más de 2 máquinas, aplicamos el algoritmo CDS
    List<FlowShopInput> bestSequence = [];
    int bestMakespan = double.maxFinite.toInt();

    for (int k = 1; k < numMachines; k++) {

      List<FlowShopInput> tempJobs =
      inputJobs.map((job) {

        Duration sumA = Duration.zero;
        Duration sumB = Duration.zero;

        for (int i = 0; i < k; i++) {
          int taskId = job.taskSequence[i].value1;
          sumA += job.taskTimesInMachines[taskId]!;
        }

        for (int i = k; i < numMachines; i++) {
          int taskId = job.taskSequence[i].value1;
          sumB += job.taskTimesInMachines[taskId]!;
        }

        Map<int, Duration> reducedTimes = {0: sumA, 1: sumB};

        return FlowShopInput(
          job.jobId,
          job.dueDate,
          job.priority,
          job.availableDate,
          [Tuple2(0, 0), Tuple2(1, 1)],

          reducedTimes,
        );
      }).toList();

      // Aplicamos Johnson sobre trabajos ficticios
      List<FlowShopInput> ordered = _getJohnsonOrderedJobs(tempJobs);
      List<int> orderedIds = ordered.map((e) => e.jobId).toList();

      // Convertimos a la secuencia original

      List<FlowShopInput> orderedOriginal =
      orderedIds

          .map((id) => inputJobs.firstWhere((job) => job.jobId == id))
          .toList();

      // Calculamos el makespan con esa secuencia
      int makespan = _calculateMakespan(orderedOriginal);

      if (makespan < bestMakespan) {
        bestMakespan = makespan;
        bestSequence = orderedOriginal;
      }
    }

    inputJobs = bestSequence;
    _schedule((a, b) => 0);
    print("Optimal sequence: ${bestSequence.map((job) => job.jobId).toList()}");
    print("Optimal makespan: $bestMakespan");
  }

  void _applyJohnsonRule(List<FlowShopInput> jobs) {
    List<FlowShopInput> conjuntoI = [];
    List<FlowShopInput> conjuntoII = [];

    for (var job in jobs) {
      Duration a = job.taskTimesInMachines[job.taskSequence[0].value1]!;
      Duration b = job.taskTimesInMachines[job.taskSequence[1].value1]!;

      if (a <= b) {
        conjuntoI.add(job);
      } else {
        conjuntoII.add(job);
      }
    }

    conjuntoI.sort(
          (a, b) => a.taskTimesInMachines[a.taskSequence[0].value1]!.compareTo(

        b.taskTimesInMachines[b.taskSequence[0].value1]!,
      ),
    );
    conjuntoII.sort(
          (a, b) => b.taskTimesInMachines[b.taskSequence[1].value1]!.compareTo(

        a.taskTimesInMachines[a.taskSequence[1].value1]!,
      ),
    );

    inputJobs = [...conjuntoI, ...conjuntoII];
    _schedule((a, b) => 0);
  }

  List<FlowShopInput> _getJohnsonOrderedJobs(List<FlowShopInput> jobs) {
    List<FlowShopInput> conjuntoI = [];
    List<FlowShopInput> conjuntoII = [];

    for (var job in jobs) {
      Duration a = job.taskTimesInMachines[0]!;
      Duration b = job.taskTimesInMachines[1]!;

      if (a <= b) {
        conjuntoI.add(job);
      } else {
        conjuntoII.add(job);
      }
    }

    conjuntoI.sort(
          (a, b) => a.taskTimesInMachines[0]!.compareTo(b.taskTimesInMachines[0]!),
    );
    conjuntoII.sort(
          (a, b) => b.taskTimesInMachines[1]!.compareTo(a.taskTimesInMachines[1]!),

    );

    return [...conjuntoI, ...conjuntoII];
  }

  int _calculateMakespan(List<FlowShopInput> jobSequence) {
    Map<int, DateTime> currentMachineAvailability = {};

    Map<int, int?> currentMachineSequence = {};
    for (var job in jobSequence) {
      for (var task in job.taskSequence) {
        int machineId = task.value2;
        currentMachineAvailability[machineId] = startDate;
        currentMachineSequence[machineId] = null;
      }
    }

    DateTime makespanEndTime = startDate;

    for (var job in jobSequence) {
      DateTime jobStartTime = job.availableDate;

      for (var task in job.taskSequence) {
        int taskId = task.value1;
        int machineId = task.value2;
        Duration duration = job.taskTimesInMachines[taskId]!;

        DateTime machineAvailable =
            currentMachineAvailability[machineId] ?? startDate;

        DateTime startTime = jobStartTime.isAfter(machineAvailable)
            ? jobStartTime
            : machineAvailable;
        startTime = _adjustForWorkingSchedule(startTime);

        final int? previousSequence =
            currentMachineSequence.putIfAbsent(machineId, () => null);
        final Duration setupDuration =
            _getSetupDuration(machineId, job.sequenceId, previousSequence);
        final Duration totalDuration = duration + setupDuration;

        DateTime endTime = _calculateEndWithSchedule(startTime, totalDuration);

        currentMachineAvailability[machineId] = endTime;
        currentMachineSequence[machineId] = job.sequenceId;
        jobStartTime = endTime;
      }

      makespanEndTime = jobStartTime.isAfter(makespanEndTime)
          ? jobStartTime
          : makespanEndTime;
    }

    return makespanEndTime.difference(startDate).inMinutes;
  }

  ///////////////////////////////////////////////////
  ///////////////ALGORITMO GENÉTICO//////////////////
  ///////////////////////////////////////////////////

  // Busca el mejor orden posible de ejecución de trabajos para minimizar el makespan
  // en un entorno Flow Shop donde cada trabajo pasa por todas las máquinas en secuencia
  void scheduleGeneticAlgorithm() {
    print("EJECUTANDO ALGORITMO GENÉTICO EN FLOW SHOP");

    // Parámetros del algoritmo genético
    const int populationSize = 50;  // Soluciones por generación
    const int generations = 100;     // Número de generaciones
    const double mutationRate = 0.1; // Probabilidad de mutación

    // Inicializar población con secuencias aleatorias
    List<List<FlowShopInput>> population = _initializePopulation(populationSize);

    // Variables para guardar el mejor individuo encontrado
    List<FlowShopInput> bestIndividual = [];
    int bestFitness = double.maxFinite.toInt();

    // Proceso evolutivo
    for (int generation = 0; generation < generations; generation++) {
      // Evaluar fitness de cada individuo (makespan)
      List<Tuple2<List<FlowShopInput>, int>> evaluated = population.map((individual) {
        return Tuple2(individual, _evaluateFitnessFlowShop(individual));
      }).toList();

      // Ordenar por fitness (menor makespan es mejor)
      evaluated.sort((a, b) => a.value2.compareTo(b.value2));

      // Actualizar mejor individuo si se encuentra uno mejor
      if (evaluated.first.value2 < bestFitness) {
        bestFitness = evaluated.first.value2;
        bestIndividual = evaluated.first.value1;
        print("Generación $generation: Mejor makespan = $bestFitness minutos");
      }

      // Generar nueva población mediante selección, cruce y mutación
      population = _generateNewPopulation(evaluated, populationSize, mutationRate);
    }

    // Asignar el mejor orden encontrado y programar los trabajos
    print("Mejor secuencia encontrada: ${bestIndividual.map((j) => j.jobId).toList()}");
    print("Makespan óptimo: $bestFitness minutos");

    inputJobs = bestIndividual;
    _schedule((a, b) => 0); // Asignar trabajos en el orden encontrado
  }

  // Genera población inicial con secuencias aleatorias de trabajos
  List<List<FlowShopInput>> _initializePopulation(int size) {
    List<List<FlowShopInput>> population = [];

    for (int i = 0; i < size; i++) {
      List<FlowShopInput> shuffled = List.from(inputJobs);
      shuffled.shuffle(); // Orden aleatorio
      population.add(shuffled);
    }

    return population;
  }

  // Evalúa el fitness (makespan) de una secuencia de trabajos en Flow Shop
  // El makespan es el tiempo total desde el inicio hasta que termina el último trabajo
  int _evaluateFitnessFlowShop(List<FlowShopInput> jobSequence) {
    // Mapa para rastrear cuándo cada máquina estará disponible
    Map<int, DateTime> machineAvailability = {};

    // Inicializar disponibilidad de todas las máquinas
    for (var job in jobSequence) {
      for (var task in job.taskSequence) {
        int machineId = task.value2;
        machineAvailability[machineId] = startDate;
      }
    }

    DateTime makespanEndTime = startDate;

    // Simular la ejecución de cada trabajo en Flow Shop
    for (var job in jobSequence) {
      DateTime jobStartTime = job.availableDate;

      // Cada trabajo pasa por todas sus tareas/máquinas en secuencia
      for (var task in job.taskSequence) {
        int taskId = task.value1;
        int machineId = task.value2;
        Duration duration = job.taskTimesInMachines[taskId]!;

        // Determinar cuándo puede comenzar esta tarea
        // Debe esperar a:
        // 1. Que el trabajo termine su tarea anterior (jobStartTime)
        // 2. Que la máquina esté disponible (machineAvailability)
        DateTime machineAvailable = machineAvailability[machineId] ?? startDate;
        DateTime startTime = jobStartTime.isAfter(machineAvailable)
            ? jobStartTime
            : machineAvailable;

        // Ajustar al horario laboral
        startTime = _adjustForWorkingSchedule(startTime);
        DateTime endTime = startTime.add(duration);
        endTime = _adjustEndTimeForWorkingSchedule(startTime, endTime);

        // Actualizar disponibilidad de la máquina
        machineAvailability[machineId] = endTime;

        // El siguiente task de este job debe esperar a que termine este
        jobStartTime = endTime;
      }

      // Actualizar makespan (tiempo en que termina el último trabajo)
      if (jobStartTime.isAfter(makespanEndTime)) {
        makespanEndTime = jobStartTime;
      }
    }

    // Retornar el makespan total en minutos
    return makespanEndTime.difference(startDate).inMinutes;
  }

  // Genera una nueva población mediante selección, cruce y mutación
  List<List<FlowShopInput>> _generateNewPopulation(
      List<Tuple2<List<FlowShopInput>, int>> evaluated,
      int size,
      double mutationRate,
      ) {
    List<List<FlowShopInput>> newPop = [];

    for (int i = 0; i < size; i++) {
      // Seleccionar dos padres mediante torneo
      final parent1 = _selectParent(evaluated);
      final parent2 = _selectParent(evaluated);

      // Crear hijo mediante cruce
      List<FlowShopInput> child = _crossover(parent1, parent2);

      // Aplicar mutación con cierta probabilidad
      if (Random().nextDouble() < mutationRate) {
        child = _mutate(child);
      }

      newPop.add(child);
    }

    return newPop;
  }

  // Selección por torneo: elige k individuos al azar y retorna el mejor
  List<FlowShopInput> _selectParent(List<Tuple2<List<FlowShopInput>, int>> evaluated) {
    int k = 5; // Tamaño del torneo

    // Seleccionar k individuos aleatorios
    final selected = List.generate(
        k,
            (_) => evaluated[Random().nextInt(evaluated.length)]
    );

    // Ordenar por fitness (menor es mejor)
    selected.sort((a, b) => a.value2.compareTo(b.value2));

    // Retornar el mejor individuo del torneo
    return selected.first.value1;
  }

  // Cruce de orden (Order Crossover - OX): combina dos padres para crear un hijo
  List<FlowShopInput> _crossover(List<FlowShopInput> p1, List<FlowShopInput> p2) {
    final length = p1.length;

    // Seleccionar punto de corte aleatorio
    final int point = Random().nextInt(length);

    // Copiar primera parte del padre 1
    final Set<int> jobIds = p1.sublist(0, point).map((j) => j.jobId).toSet();

    // Crear hijo: primera parte de p1 + resto de p2 sin repetir
    final List<FlowShopInput> child = [
      ...p1.sublist(0, point),
      ...p2.where((j) => !jobIds.contains(j.jobId)),
    ];

    return child;
  }

  // Mutación por intercambio: cambia de posición dos trabajos aleatorios
  List<FlowShopInput> _mutate(List<FlowShopInput> individual) {
    if (individual.length < 2) return individual;

    // Seleccionar dos posiciones aleatorias
    int i = Random().nextInt(individual.length);
    int j = Random().nextInt(individual.length);

    // Intercambiar trabajos
    final temp = individual[i];
    individual[i] = individual[j];
    individual[j] = temp;

    return individual;
  }
}
  
