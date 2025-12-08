import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class JobShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; // Horas de trabajo

  List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  // job id | due date | priority | available date

  Map<int, List<Tuple2<int, Duration>>> jobRoutes = {};
  // job id -> List of <machine id, duration>
  // Cada trabajo tiene su propia ruta y duración en las máquinas

  List<DateTime> machineAvailability = [];
  // Registro de disponibilidad de cada máquina

  List<Tuple3<int, int, Tuple2<DateTime, DateTime>>> output = [];
  // job id | machine id | <start, end time>

  JobShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.jobRoutes,
    String rule,
  ) {
    // Inicializar la disponibilidad de las máquinas
    int totalMachines = _getTotalMachines();
    machineAvailability = List.generate(totalMachines, (_) => startDate);

    // Elegir el algoritmo según la regla proporcionada
    switch (rule) {
      case "SPT":
        sptRule();
        break;
      case "LPT":
        lptRule();
        break;
      case "MVR":
        mvrRule();
        break;
    }

    printOutput();
  }

  // Obtiene el número total de máquinas en uso
  int _getTotalMachines() {
    final machineIds = jobRoutes.values
        .expand((routes) => routes.map((route) => route.value1))
        .toSet();
    return machineIds.length;
  }

  // Regla SPT: Ordena trabajos por tiempo total de procesamiento más corto
  void sptRule() {
    inputJobs.sort((a, b) {
      int totalTimeA = _calculateTotalProcessingTime(a.value1);
      int totalTimeB = _calculateTotalProcessingTime(b.value1);
      return totalTimeA.compareTo(totalTimeB);
    });
    assignJobs();
  }

  // Regla LPT: Ordena trabajos por tiempo total de procesamiento más largo
  void lptRule() {
    inputJobs.sort((a, b) {
      int totalTimeA = _calculateTotalProcessingTime(a.value1);
      int totalTimeB = _calculateTotalProcessingTime(b.value1);
      return totalTimeB.compareTo(totalTimeA);
    });
    assignJobs();
  }

  // Regla MVR: Minimiza la variancia en la carga de máquinas
  void mvrRule() {
    inputJobs.sort((a, b) {
      return a.value3.compareTo(b.value3); // Ordenar por fecha disponible
    });
    assignJobsMVR();
  }

  // Calcula el tiempo total de procesamiento de un trabajo
  int _calculateTotalProcessingTime(int jobId) {
    return jobRoutes[jobId]!
        .map((route) => route.value2.inMinutes)
        .reduce((a, b) => a + b);
  }

  // Asigna trabajos según las reglas seleccionadas
  void assignJobs() {
    for (var job in inputJobs) {
      int jobId = job.value1;
      DateTime jobAvailable = job.value4;

      for (var route in jobRoutes[jobId]!) {
        int machineId = route.value1;
        Duration processTime = route.value2;

        DateTime machineFree = machineAvailability[machineId];
        DateTime startTime =
            jobAvailable.isAfter(machineFree) ? jobAvailable : machineFree;

        startTime = adjustForWorkingSchedule(startTime);
        DateTime endTime = startTime.add(processTime);
        endTime = adjustEndTimeForWorkingSchedule(startTime, endTime);

        // Agregar al resultado
        output.add(Tuple3(jobId, machineId, Tuple2(startTime, endTime)));

        // Actualizar disponibilidad de la máquina
        machineAvailability[machineId] = endTime;
        jobAvailable = endTime;
      }
    }
  }

  void assignJobsMVR() {
    // Inicializa las cargas de las máquinas en 0
    Map<int, Duration> machineLoads = {
      for (int i = 0; i < machineAvailability.length; i++) i: Duration.zero
    };

    for (var job in inputJobs) {
      int jobId = job.value1;

      for (var route in jobRoutes[jobId]!) {
        int machineId = route.value1;
        Duration processTime = route.value2;

        // Verifica y suma el tiempo de procesamiento a la carga de la máquina
        machineLoads[machineId] =
            (machineLoads[machineId] ?? Duration.zero) + processTime;

        assignJobs();
      }
    }
  }

  // Ajusta el inicio del trabajo para respetar las horas laborales
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

  // Ajusta el final del trabajo según el horario laboral
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

  // Imprime los resultados del programa
  void printOutput() {
    print("Resultados del Job Shop:");
    for (var result in output) {
      print(
          "Job ${result.value1} on Machine ${result.value2}: Start ${result.value3.value1}, End ${result.value3.value2}");
    }
  }
}
