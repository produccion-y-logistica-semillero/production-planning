import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class FlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17
  List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  //the input comes like a table of type
  //  job id   |     due date        |       priority  | Available date
  //  1         |   2024/8/30/6:00    |         1       | 2024/8/30/6:00
  //  2         |   2024/8/30/6:00    |         3       | 2024/8/30/6:00
  //  3         |   2024/8/30/6:00    |         2       | 2024/8/30/6:00

  List<List<Duration>> timeMatrix =
      []; //matrix of time it takes the task in each machine type
  //  The first list (rows) are the indexes of jobs, and the inside list (columns) are the times in each machine type
  //  the indexes in these lists (matrix) point to the same indexes in the list of inputJobs and machineId's
  //          :   0   |   1   |   2   |   3   |
  //      0     10:25 | 01:30 | 02:45 | 00:45 |
  //      1     08:25 | 00:30 | 02:50 | 00:12 |

  List<Tuple3<int, List<Tuple2<DateTime, DateTime>>, DateTime>> output = [];
  //         |   Machine index 0   |   Machine index 1  |  Machine index 2    ....| DUE DATE
  // job 1   |   <10:00, 12:00>    |   <14:00, 17:00>   |    <18:00, 20:30>   ....|
  // job 2   |   <12:00, 13:45>    |   <17:00, 18:00>   |    <20:30, 21:30>   ....|

  // List of machine availability times
  List<DateTime> machineAvailability = [];

  FlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.timeMatrix,
    String rule,
  ) {
    // Initialize machine availability with start date
    for (int i = 0; i < timeMatrix[0].length; i++) {
      machineAvailability.add(startDate);
    }

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
      case "JOHNSON":
        johnsonRule();
        break;
      case "JOHNSON3":
        johnson3();
        break;
      case "JOHNSONM":
        cdsAlgorithm();
        break;
    }
    printTimeMatrix();
    printOutput();
  }

  // Regla EDD: Ordena los trabajos por la fecha de vencimiento más cercana
  void eddRule() {
    inputJobs.sort((a, b) => a.value2.compareTo(b.value2));
    assignJobs();
  }

  // Regla SPT: Ordena los trabajos por el tiempo de procesamiento más corto
  void sptRule() {
    inputJobs.sort((a, b) => timeMatrix[inputJobs.indexOf(a)]
        .reduce((v1, v2) => v1 + v2)
        .compareTo(
            timeMatrix[inputJobs.indexOf(b)].reduce((v1, v2) => v1 + v2)));
    assignJobs();
  }

  // Regla LPT: Ordena los trabajos por el tiempo de procesamiento más largo
  void lptRule() {
    inputJobs.sort((a, b) => timeMatrix[inputJobs.indexOf(b)]
        .reduce((v1, v2) => v1 + v2)
        .compareTo(
            timeMatrix[inputJobs.indexOf(a)].reduce((v1, v2) => v1 + v2)));
    assignJobs();
  }

  // Regla FIFO: Ordena los trabajos por la fecha disponible (First In, First Out)
  void fifoRule() {
    inputJobs.sort((a, b) => a.value4.compareTo(b.value4));
    assignJobs();
  }

  // Función para asignar trabajos a las máquinas
  void assignJobs() {
    for (int jobIndex = 0; jobIndex < inputJobs.length; jobIndex++) {
      DateTime jobAvailableTime = inputJobs[jobIndex].value4;
      List<Tuple2<DateTime, DateTime>> jobSchedule = [];

      for (int machineIndex = 0;
          machineIndex < timeMatrix[jobIndex].length;
          machineIndex++) {
        Duration processingTime = timeMatrix[jobIndex][machineIndex];

        // La máquina está disponible en su próximo tiempo libre o cuando el trabajo esté disponible, el que sea más tarde
        DateTime startTime =
            jobAvailableTime.isAfter(machineAvailability[machineIndex])
                ? jobAvailableTime
                : machineAvailability[machineIndex];

        // Ajustar para el horario laboral
        startTime = adjustForWorkingSchedule(startTime);
        DateTime endTime = startTime.add(processingTime);
        endTime = adjustEndTimeForWorkingSchedule(startTime, endTime);

        jobSchedule.add(Tuple2(startTime, endTime));

        // Actualizar la disponibilidad de la máquina
        machineAvailability[machineIndex] = endTime;

        // El final de esta máquina es cuando el trabajo estará disponible para la siguiente
        jobAvailableTime = endTime;
      }

      output.add(Tuple3(
          inputJobs[jobIndex].value1, jobSchedule, inputJobs[jobIndex].value2));
    }
  }

  // Ajusta el tiempo de inicio para cumplir con el horario laboral
  DateTime adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour ||
        (start.hour == workingStart.hour &&
            start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour,
          workingStart.minute);
    } else if (start.hour > workingEnd.hour ||
        (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour,
          workingStart.minute);
    }
    return start;
  }

  // Ajusta el tiempo de finalización según el horario laboral
  DateTime adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(
        start.year, start.month, start.day, workingEnd.hour, workingEnd.minute);

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1,
              workingSchedule.value1.hour, workingSchedule.value1.minute)
          .add(remainingTime);
    }

    return end;
  }

  void johnsonRule() {
    /**
      1. create a list of jobs with their indexes
      2. sort the jobs with the rule
      3. schedule the jobs
      
     */

    try {
      if (timeMatrix.isEmpty || timeMatrix[0].length != 2) {
        throw Exception(
            "The Johnson's rule can only be applied to exactly two machines.");
      }

      for (var row in timeMatrix) {
        if (row.length != 2) {
          throw Exception(
              "Each job must have exactly two durations specified for the two machines.");
        }
      }

      // duration in machine 1 < duration in machine 2
      List<int> conjuntoI = [];
      // duration in machine 1 > duration in machine 2
      List<int> conjuntoII = [];

      for (int i = 0; i < timeMatrix.length; i++) {
        if (timeMatrix[i][0] < timeMatrix[i][1]) {
          conjuntoI.add(i);
        } else {
          conjuntoII.add(i);
        }
      }

      // SPT = sort from smallest to largest
      conjuntoI.sort((a, b) => timeMatrix[a][0].compareTo(timeMatrix[b][0]));
      // LPT = sort fromt largest to smallest
      conjuntoII.sort((a, b) => timeMatrix[b][1].compareTo(timeMatrix[a][1]));

      print("Sorted set I: $conjuntoI");
      print("Sorted set II: $conjuntoII");

      List<int> jobIndices = [...conjuntoI, ...conjuntoII];
      print("Sorted jobIndices: $jobIndices");

      DateTime currentTimeMachine1 = startDate;
      DateTime currentTimeMachine2 = startDate;

      for (int jobIndex in jobIndices) {
        // these store the job's duration  in the machine
        Duration timeOnMachine1 = timeMatrix[jobIndex][0];
        Duration timeOnMachine2 = timeMatrix[jobIndex][1];

        // current time in the machine 1
        DateTime startTimeMachine1 = currentTimeMachine1;
        // end time is equal to currentTime plus timeOnMachine
        DateTime endTimeMachine1 = currentTimeMachine1.add(timeOnMachine1);
        currentTimeMachine1 = endTimeMachine1;

        DateTime startTimeMachine2 =
            // if currentTimeMachine2 is after endTimeMachine is because this is busy; so startTimeMachine goint to be the hour where Machine2 is free. Otherwise
            // startTime2 can be the same endTime1
            (currentTimeMachine2.isAfter(endTimeMachine1))
                ? currentTimeMachine2
                : endTimeMachine1;
        DateTime endTimeMachine2 = startTimeMachine2.add(timeOnMachine2);
        currentTimeMachine2 = endTimeMachine2;

        // add the job id and its schedule for machine 1 and machine 2 (is the same tuple created before)
        output.add(Tuple3(
          jobIndex,
          [
            Tuple2(startTimeMachine1, endTimeMachine1),
            Tuple2(startTimeMachine2, endTimeMachine2),
          ],
          inputJobs[jobIndex].value2,
        ));

        // Print statements to observe the scheduling process (error tests)
        print(
            "Job $jobIndex scheduled on Machine 1: $startTimeMachine1 - $endTimeMachine1");
        print(
            "Job $jobIndex scheduled on Machine 2: $startTimeMachine2 - $endTimeMachine2");
      }
    } catch (e) {
      print("Error while applying Johnson's rule: $e");
      throw Exception("An error occurred during job scheduling: $e");
    }
  }

  void johnson3() {
    try {
      if (timeMatrix.isEmpty || timeMatrix[0].length != 3) {
        throw Exception(
            "The Johnson's rule can only be applied to exactly three machines.");
      }

      List<int> conjuntoI = [];
      List<int> conjuntoII = [];
      List<int> p1Prime = [];
      List<int> p2Prime = [];

      for (int jobIndex = 0; jobIndex < timeMatrix.length; jobIndex++) {
        int p1j = timeMatrix[jobIndex][0].inMinutes +
            timeMatrix[jobIndex][1].inMinutes; // p'_{1j}
        int p2j = timeMatrix[jobIndex][1].inMinutes +
            timeMatrix[jobIndex][2].inMinutes; // p'_{2j}
        p1Prime.add(p1j);
        p2Prime.add(p2j);

        if (p1j <= p2j) {
          conjuntoI.add(jobIndex);
        } else {
          conjuntoII.add(jobIndex);
        }
      }

      // sort groups, its the same than johnson with two machines; the first set is with SPT and the second one is with LPT.
      conjuntoI.sort((a, b) => p1Prime[a].compareTo(p1Prime[b]));
      conjuntoII.sort((a, b) => p2Prime[b].compareTo(p2Prime[a]));

      // Join both sets.
      List<int> jobIndices = [...conjuntoI, ...conjuntoII];

      DateTime currentTimeMachine1 = startDate;
      DateTime currentTimeMachine2 = startDate;
      DateTime currentTimeMachine3 = startDate;

      for (int jobIndex in jobIndices) {
        Duration timeOnMachine1 = timeMatrix[jobIndex][0];
        Duration timeOnMachine2 = timeMatrix[jobIndex][1];
        Duration timeOnMachine3 = timeMatrix[jobIndex][2];

        // machine 1
        DateTime startTimeMachine1 = currentTimeMachine1;
        DateTime endTimeMachine1 = startTimeMachine1.add(timeOnMachine1);
        currentTimeMachine1 = endTimeMachine1;

        // machine 2
        DateTime startTimeMachine2 =
            currentTimeMachine2.isAfter(endTimeMachine1)
                ? currentTimeMachine2
                : endTimeMachine1;
        DateTime endTimeMachine2 = startTimeMachine2.add(timeOnMachine2);
        currentTimeMachine2 = endTimeMachine2;

        // machine 3
        DateTime startTimeMachine3 =
            currentTimeMachine3.isAfter(endTimeMachine2)
                ? currentTimeMachine3
                : endTimeMachine2;
        DateTime endTimeMachine3 = startTimeMachine3.add(timeOnMachine3);
        currentTimeMachine3 = endTimeMachine3;

        output.add(Tuple3<int, List<Tuple2<DateTime, DateTime>>, DateTime>(
          // job´s id
          inputJobs[jobIndex].value1,
          [
            Tuple2(startTimeMachine1, endTimeMachine1),
            Tuple2(startTimeMachine2, endTimeMachine2),
            Tuple2(startTimeMachine3, endTimeMachine3),
          ],
          // due date
          inputJobs[jobIndex].value2,
        ));
      }

      print("Secuencia de trabajos (índices): $jobIndices");
    } catch (e) {
      print("An error occurred during job scheduling for three machines: $e");
    }
  }

  // this algorithm can work for three machines, but the makespan can be the same in some cases and with the last algorith "johnson3" is exactly.
  void cdsAlgorithm() {
    try {
      if (timeMatrix.isEmpty || timeMatrix[0].length < 3) {
        throw Exception(
            "The C.D.S´s rule can only be applied to three machines or more.");
      }

      int numJobs = timeMatrix.length;
      int numMachines = timeMatrix[0].length;

      List<int> bestSequence = [];
      int bestMakespan = double.maxFinite.toInt();

      // here its creating the subcombinations (m-1)
      for (int k = 1; k < numMachines; k++) {
        List<List<int>> subProblemMatrix =
            List.generate(numJobs, (_) => List<int>.filled(2, 0));

        for (int j = 0; j < numJobs; j++) {
          //  (p'_{1j})
          subProblemMatrix[j][0] = timeMatrix[j]
              .sublist(0, k)
              .fold(0, (sum, duration) => sum + duration.inMinutes);

          // (p'_{2j})
          subProblemMatrix[j][1] = timeMatrix[j]
              .sublist(k, numMachines)
              .fold(0, (sum, duration) => sum + duration.inMinutes);
        }

        // johnson algorithm for two machines
        List<int> conjuntoI = [];
        List<int> conjuntoII = [];

        for (int j = 0; j < subProblemMatrix.length; j++) {
          if (subProblemMatrix[j][0] <= subProblemMatrix[j][1]) {
            conjuntoI.add(j);
          } else {
            conjuntoII.add(j);
          }
        }

        // first set (SPT)
        conjuntoI.sort(
            (a, b) => subProblemMatrix[a][0].compareTo(subProblemMatrix[b][0]));

        // second set (LPT)
        conjuntoII.sort(
            (a, b) => subProblemMatrix[b][1].compareTo(subProblemMatrix[a][1]));

        // join sets
        List<int> sequence = [...conjuntoI, ...conjuntoII];

        //makespan
        int makespan = 0;
        List<int> endTimes = List<int>.filled(numMachines, 0);

        for (int jobIndex in sequence) {
          for (int machine = 0; machine < numMachines; machine++) {
            int startTime =
                (machine == 0) ? endTimes[0] : endTimes[machine - 1];
            endTimes[machine] =
                startTime + timeMatrix[jobIndex][machine].inMinutes;
          }
        }

        makespan = endTimes.last;

        if (makespan < bestMakespan) {
          bestMakespan = makespan;
          bestSequence = sequence;
        }
      }

      List<DateTime> currentTimeMachines =
          List<DateTime>.filled(numMachines, startDate);

      for (int jobIndex in bestSequence) {
        List<Tuple2<DateTime, DateTime>> machineSchedules = [];

        for (int machine = 0; machine < numMachines; machine++) {
          Duration jobDuration = timeMatrix[jobIndex][machine];
          DateTime startTime = (machine == 0)
              ? currentTimeMachines[0]
              : currentTimeMachines[machine - 1]
                      .isAfter(currentTimeMachines[machine])
                  ? currentTimeMachines[machine - 1]
                  : currentTimeMachines[machine];
          DateTime endTime = startTime.add(jobDuration);
          // update availability time
          currentTimeMachines[machine] = endTime;

          print(
              "Trabajo ${inputJobs[jobIndex].value1} programado en Máquina ${machine + 1}: Inicio $startTime - Fin $endTime");

          machineSchedules.add(Tuple2(startTime, endTime));
        }

        output.add(Tuple3<int, List<Tuple2<DateTime, DateTime>>, DateTime>(
          // job´s id
          inputJobs[jobIndex].value1,
          machineSchedules,
          // due date
          inputJobs[jobIndex].value2,
        ));
      }

      print("Secuencia óptima: $bestSequence");
      print("Makespan óptimo: $bestMakespan");
    } catch (e) {
      print("Error in C.D.S´s algorithm: $e");
    }
  }

  // Imprimir el resultado de las asignaciones de trabajos
  void printOutput() {
    print("Resultado de la asignación de trabajos:");
    for (var result in output) {
      print('Job ${result.value1} Schedule:');
      for (var schedule in result.value2) {
        print('  Start: ${schedule.value1}, End: ${schedule.value2}');
      }
    }
  }

  void printTimeMatrix() {
    print('Time Matrix:');
    for (int i = 0; i < timeMatrix.length; i++) {
      print(
          'Job ${i + 1}: ${timeMatrix[i].map((d) => d.toString()).join(', ')}');
    }
  }
}
