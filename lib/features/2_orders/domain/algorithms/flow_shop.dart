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
 
  List<List<Duration>> timeMatrix = []; //matrix of time it takes the task in each machine type
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
    inputJobs.sort((a, b) =>
        timeMatrix[inputJobs.indexOf(a)].reduce((v1, v2) => v1 + v2)
            .compareTo(timeMatrix[inputJobs.indexOf(b)].reduce((v1, v2) => v1 + v2)));
    assignJobs();
  }

  // Regla LPT: Ordena los trabajos por el tiempo de procesamiento más largo
  void lptRule() {
    inputJobs.sort((a, b) =>
        timeMatrix[inputJobs.indexOf(b)].reduce((v1, v2) => v1 + v2)
            .compareTo(timeMatrix[inputJobs.indexOf(a)].reduce((v1, v2) => v1 + v2)));
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

      for (int machineIndex = 0; machineIndex < timeMatrix[jobIndex].length; machineIndex++) {
        Duration processingTime = timeMatrix[jobIndex][machineIndex];

        // La máquina está disponible en su próximo tiempo libre o cuando el trabajo esté disponible, el que sea más tarde
        DateTime startTime = jobAvailableTime.isAfter(machineAvailability[machineIndex])
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

      output.add(Tuple3(inputJobs[jobIndex].value1, jobSchedule, inputJobs[jobIndex].value2));
    }
  }

  // Ajusta el tiempo de inicio para cumplir con el horario laboral
  DateTime adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour ||
        (start.hour == workingStart.hour && start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour, workingStart.minute);
    } else if (start.hour > workingEnd.hour || (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour, workingStart.minute);
    }
    return start;
  }

  // Ajusta el tiempo de finalización según el horario laboral
  DateTime adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(start.year, start.month, start.day, workingEnd.hour, workingEnd.minute);

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1, workingSchedule.value1.hour, workingSchedule.value1.minute)
          .add(remainingTime);
    }

    return end;
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
      print('Job ${i + 1}: ${timeMatrix[i].map((d) => d.toString()).join(', ')}');
    }
  }
}

