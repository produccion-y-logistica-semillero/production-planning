import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class SingleMachine {
  final int machineId;
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17
  List<Tuple5<int, Duration, DateTime, int, DateTime>> input = [];
  //the input comes like a table of type
  //  work id   |     unique machine duration   |     due date        |       priority    |     Available date
  //  1         |         15:30                 |   2024/8/30/6:00    |         1         |     2024/8/28/6:00 
  //  2         |         20:41                 |   2024/8/30/6:00    |         3         |     2024/8/28/6:00
  //  3         |         01:25                 |   2024/8/30/6:00    |         2         |     2024/8/28/6:00

  List<Tuple6<int, Duration, DateTime, DateTime, DateTime, Duration>> output = [];
  //the output goes like a table of type
  //  work id   |   processing time   |   start date    |     End date    |     due date        |     Rest (Retraso)    
  //  1         |       01:30         |  26/09/24/10:00 | 26/09/24/11:30  |   2024/8/30/6:00    |     00:00
  //  2         |       02:30         |  26/09/24/11:30 | 26/09/24/14:00  |   2024/8/30/6:00    |     00:00

  SingleMachine(
    this.machineId,
    this.startDate,
    this.workingSchedule,
    this.input,
    String rule,
  ) {
    switch (rule) {
      //case "JHONSON":jhonsonRule();break;
      case "EDD": eddrule(); break;
      case "SPT": sptrule(); break;
      case "LPT": lptrule(); break;
      case "FIFO": fiforule(); break;
      case "WSPT": wsptrule(); break;
      case "EDD_ADAPTADO": eddruleadaptado(); break;
      case "SPT_ADAPTADO": sptruleadaptado(); break;
      case "LPT_ADAPTADO": lptruleadaptado(); break;
      case "FIFO_ADAPTADO": fiforuleadaptado(); break;
      case "WSPT_ADAPTADO": wsptruleadaptado(); break;
      case "MINSLACK": scheduleMinimumSlack(); break;
      case "CR": scheduleCriticalRatio(); break;
        
    }
  }
// Implementación de la regla de EDD (Earliest Due Date)
void eddrule() {
  // Organizar las tareas por orden de entrega
  input.sort((a, b) => a.value3.compareTo(b.value3));

  // Obtener la fecha y hora de inicio de la planta
  DateTime startWorkDateTime = DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
    workingSchedule.value1.hour,
    workingSchedule.value1.minute,
  );

  // Obtener el trabajo más temprano
  DateTime earliestJobAvailableTime = input[0].value5;

  // El tiempo de inicio es el mayor entre el tiempo de inicio de la planta y el momento en que está disponible el primer trabajo
  DateTime inicioPlaneacion = earliestJobAvailableTime.isBefore(startWorkDateTime)
      ? startWorkDateTime
      : earliestJobAvailableTime;

  for (var tuple in input) {
    int job = tuple.value1;
    Duration duracion = tuple.value2;
    DateTime duedate = tuple.value3;
    DateTime inicio;
    DateTime fin; 
    Duration retardo;

    // Para asignar el inicio, debo ver si iniciando donde está más lo que se demora alcanza a caber en el día
    int tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + duracion.inMinutes;
    int findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    if (tiemptot < findia) { // Cabe la planeación en el mismo día
      inicio = inicioPlaneacion;
    } else { // No cabe la planeación en el mismo día
      // Toca comenzar desde el otro día
      inicioPlaneacion = inicioPlaneacion.add(Duration(days: 1));
      // Resetear desde la hora de inicio
      inicioPlaneacion = DateTime(
        inicioPlaneacion.year,
        inicioPlaneacion.month,
        inicioPlaneacion.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
      // Asigno la hora de inicio
      inicio = inicioPlaneacion;
    }
    
    // El final del tiempo se calcula con la duración del trabajo
    inicioPlaneacion = inicioPlaneacion.add(duracion);
    fin = inicioPlaneacion;

    // Ahora ver si hay tardanza
    if (fin.isAfter(duedate)) { // Si fin está después del duedate es porque hay tardanza
      retardo = fin.difference(duedate);
    } else { // No hay tardanza
      retardo = Duration.zero; 
    }

    // Añado esto en el output
    output.add(Tuple6(
      job,
      duracion,
      inicio,
      fin,
      duedate,
      retardo,
    ));
  }
}

void sptrule() {
  // Organizar las tareas por orden de entrega
  input.sort((a, b) => a.value2.compareTo(b.value2));

  // Imprimimos la lista ordenada
  for (var tuple in input) {
    print('(${tuple.value1}, ${tuple.value2}, ${tuple.value3}, ${tuple.value4}, ${tuple.value5})');
  }

  // Calcule fecha de inicio y fecha de finalización
  DateTime startDateTime = DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
    workingSchedule.value1.hour,
    workingSchedule.value1.minute,
  );

  TimeOfDay timeinit = TimeOfDay.fromDateTime(input[0].value5);
  DateTime jobStartTime = DateTime(
    input[0].value5.year,
    input[0].value5.month,
    input[0].value5.day,
    timeinit.hour,
    timeinit.minute,
  );

  DateTime inittiemp = jobStartTime.isBefore(startDateTime) ? startDateTime : jobStartTime;

  DateTime inicioPlaneacion = DateTime(
    inittiemp.year,
    inittiemp.month,
    inittiemp.day,
    inittiemp.hour,
    inittiemp.minute,
  );

  int job;
  Duration duracion;
  DateTime inicio;
  DateTime fin;
  DateTime duedate;
  Duration retardo;
  int tiemptot;
  int findia;

  for (var tuple in input) {
    job = tuple.value1;
    duracion = tuple.value2;
    duedate = tuple.value3;

    // Asignar el inicio
    tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + tuple.value2.inMinutes;
    findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    if (tiemptot < findia) {
      inicio = inicioPlaneacion;
    } else {
      // Comenzar desde el siguiente día
      inicioPlaneacion = inicioPlaneacion.add(Duration(days: 1));
      inicioPlaneacion = DateTime(
        inicioPlaneacion.year,
        inicioPlaneacion.month,
        inicioPlaneacion.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
      inicio = inicioPlaneacion;
    }

    // Calcular la fecha final
    inicioPlaneacion = inicioPlaneacion.add(tuple.value2);
    fin = inicioPlaneacion;

    // Verificar tardanza
    if (fin.isAfter(duedate)) {
      retardo = fin.difference(duedate);
    } else {
      retardo = Duration.zero;
    }

    output.add(Tuple6(job, duracion, inicio, fin, duedate, retardo));
  }
}

void lptrule() {
  // Organizar las tareas por orden de entrega
  input.sort((a, b) => b.value2.compareTo(a.value2));

  // Imprimimos la lista ordenada
  for (var tuple in input) {
    print('(${tuple.value1}, ${tuple.value2}, ${tuple.value3}, ${tuple.value4}, ${tuple.value5})');
  }

  // Calcule fecha de inicio y fecha de finalización
  DateTime startDateTime = DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
    workingSchedule.value1.hour,
    workingSchedule.value1.minute,
  );

  TimeOfDay timeinit = TimeOfDay.fromDateTime(input[0].value5);
  DateTime jobStartTime = DateTime(
    input[0].value5.year,
    input[0].value5.month,
    input[0].value5.day,
    timeinit.hour,
    timeinit.minute,
  );

  DateTime inittiemp = jobStartTime.isBefore(startDateTime) ? startDateTime : jobStartTime;

  DateTime inicioPlaneacion = DateTime(
    inittiemp.year,
    inittiemp.month,
    inittiemp.day,
    inittiemp.hour,
    inittiemp.minute,
  );

  int job;
  Duration duracion;
  DateTime inicio;
  DateTime fin;
  DateTime duedate;
  Duration retardo;
  int tiemptot;
  int findia;

  for (var tuple in input) {
    job = tuple.value1;
    duracion = tuple.value2;
    duedate = tuple.value3;

    // Asignar el inicio
    tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + tuple.value2.inMinutes;
    findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    if (tiemptot < findia) {
      inicio = inicioPlaneacion;
    } else {
      // Comenzar desde el siguiente día
      inicioPlaneacion = inicioPlaneacion.add(Duration(days: 1));
      inicioPlaneacion = DateTime(
        inicioPlaneacion.year,
        inicioPlaneacion.month,
        inicioPlaneacion.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
      inicio = inicioPlaneacion;
    }

    // Calcular la fecha final
    inicioPlaneacion = inicioPlaneacion.add(tuple.value2);
    fin = inicioPlaneacion;

    // Verificar tardanza
    if (fin.isAfter(duedate)) {
      retardo = fin.difference(duedate);
    } else {
      retardo = Duration.zero;
    }

    output.add(Tuple6(job, duracion, inicio, fin, duedate, retardo));
  }
}

void fiforule() {
  // Organizar las tareas por orden de entrega
  input.sort((a, b) => a.value5.compareTo(b.value5));

  // Imprimimos la lista ordenada
  for (var tuple in input) {
    print('(${tuple.value1}, ${tuple.value2}, ${tuple.value3}, ${tuple.value4}, ${tuple.value5})');
  }

  // Calcule fecha de inicio y fecha de finalización
  DateTime startDateTime = DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
    workingSchedule.value1.hour,
    workingSchedule.value1.minute,
  );

  TimeOfDay timeinit = TimeOfDay.fromDateTime(input[0].value5);
  DateTime jobStartTime = DateTime(
    input[0].value5.year,
    input[0].value5.month,
    input[0].value5.day,
    timeinit.hour,
    timeinit.minute,
  );

  DateTime inittiemp = jobStartTime.isBefore(startDateTime) ? startDateTime : jobStartTime;

  DateTime inicioPlaneacion = DateTime(
    inittiemp.year,
    inittiemp.month,
    inittiemp.day,
    inittiemp.hour,
    inittiemp.minute,
  );

  int job;
  Duration duracion;
  DateTime inicio;
  DateTime fin;
  DateTime duedate;
  Duration retardo;
  int tiemptot;
  int findia;

  for (var tuple in input) {
    job = tuple.value1;
    duracion = tuple.value2;
    duedate = tuple.value3;

    // Asignar el inicio
    tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + tuple.value2.inMinutes;
    findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    if (tiemptot < findia) {
      inicio = inicioPlaneacion;
    } else {
      // Comenzar desde el siguiente día
      inicioPlaneacion = inicioPlaneacion.add(Duration(days: 1));
      inicioPlaneacion = DateTime(
        inicioPlaneacion.year,
        inicioPlaneacion.month,
        inicioPlaneacion.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
      inicio = inicioPlaneacion;
    }

    // Calcular la fecha final
    inicioPlaneacion = inicioPlaneacion.add(tuple.value2);
    fin = inicioPlaneacion;

    // Verificar tardanza
    if (fin.isAfter(duedate)) {
      retardo = fin.difference(duedate);
    } else {
      retardo = Duration.zero;
    }

    output.add(Tuple6(job, duracion, inicio, fin, duedate, retardo));
  }
}

void wsptrule() {
  int tiemproces;
  List<double> wspt = [];
  for (var tuple in input) {
    // Paso tiempos de proceso a minutos
    tiemproces = tuple.value2.inHours * 60 + tuple.value2.inMinutes;
    wspt.add(tuple.value4 / tiemproces);
  }

  // Organizo la lista de tuplas según el indicador WSPT de mayor a menor
  for (int i = 0; i < input.length - 1; i++) {
    for (int j = 0; j < input.length - i - 1; j++) {
      if (wspt[j] < wspt[j + 1]) {
        // Intercambiar lista[j] y lista[j + 1]
        double temp = wspt[j];
        wspt[j] = wspt[j + 1];
        wspt[j + 1] = temp;

        var tempTuple = input[j];
        input[j] = input[j + 1];
        input[j + 1] = tempTuple;
      }
    }
  }

  // Imprimimos la lista ordenada
  for (var tuple in input) {
    print('(${tuple.value1}, ${tuple.value2}, ${tuple.value3}, ${tuple.value4}, ${tuple.value5})');
  }

  // Calcule fecha de inicio y fecha de finalización
  DateTime startDateTime = DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
    workingSchedule.value1.hour,
    workingSchedule.value1.minute,
  );

  TimeOfDay timeinit = TimeOfDay.fromDateTime(input[0].value5);
  DateTime jobStartTime = DateTime(
    input[0].value5.year,
    input[0].value5.month,
    input[0].value5.day,
    timeinit.hour,
    timeinit.minute,
  );

  DateTime inittiemp = jobStartTime.isBefore(startDateTime) ? startDateTime : jobStartTime;

  DateTime inicioPlaneacion = DateTime(
    inittiemp.year,
    inittiemp.month,
    inittiemp.day,
    inittiemp.hour,
    inittiemp.minute,
  );

  int job;
  Duration duracion;
  DateTime inicio;
  DateTime fin;
  DateTime duedate;
  Duration retardo;
  int tiemptot;
  int findia;

  for (var tuple in input) {
    job = tuple.value1;
    duracion = tuple.value2;
    duedate = tuple.value3;

    // Asignar el inicio
    tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + tuple.value2.inMinutes;
    findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    if (tiemptot < findia) {
      inicio = inicioPlaneacion;
    } else {
      // Comenzar desde el siguiente día
      inicioPlaneacion = inicioPlaneacion.add(Duration(days: 1));
      inicioPlaneacion = DateTime(
        inicioPlaneacion.year,
        inicioPlaneacion.month,
        inicioPlaneacion.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
      inicio = inicioPlaneacion;
    }

    // Calcular la fecha final
    inicioPlaneacion = inicioPlaneacion.add(tuple.value2);
    fin = inicioPlaneacion;

    // Verificar tardanza
    if (fin.isAfter(duedate)) {
      retardo = fin.difference(duedate);
    } else {
      retardo = Duration.zero;
    }

    output.add(Tuple6(job, duracion, inicio, fin, duedate, retardo));
  }
}
  
 void eddruleadaptado() {
  // Ordenar las tareas por su fecha de vencimiento
  input.sort((a, b) => a.value3.compareTo(b.value3));

  // Imprimimos la lista ordenada
  for (var tuple in input) {
    print('(${tuple.value1}, ${tuple.value2}, ${tuple.value3}, ${tuple.value4}, ${tuple.value5})');
  }

  // Calcule fecha de inicio y fecha de finalización
  TimeOfDay timeinit = TimeOfDay.fromDateTime(input[0].value5);
  int time1InMinutes = timeinit.hour * 60 + timeinit.minute;
  int time2InMinutes = workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;

  TimeOfDay inittiemp;
  if (time1InMinutes < time2InMinutes) {
    inittiemp = workingSchedule.value1;
  } else {
    inittiemp = timeinit;
  }

  DateTime inicioPlaneacion = DateTime(
    input[0].value5.year,
    input[0].value5.month,
    input[0].value5.day,
    inittiemp.hour,
    inittiemp.minute,
  );

  int job;
  Duration duracion;
  DateTime inicio;
  DateTime fin;
  DateTime duedate;
  Duration retardo;
  int tiemptot;
  int findia;

  for (var tuple in input) {
    job = tuple.value1;
    duracion = tuple.value2;
    duedate = tuple.value3;

    // Asignar el inicio
    tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + duracion.inMinutes;
    findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    if (tiemptot < findia) {
      inicio = inicioPlaneacion;
    } else {
      // Comenzar desde el siguiente día
      inicioPlaneacion = inicioPlaneacion.add(Duration(days: 1));
      inicioPlaneacion = DateTime(
        inicioPlaneacion.year,
        inicioPlaneacion.month,
        inicioPlaneacion.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
      inicio = inicioPlaneacion;
    }

    // Calcular la fecha final
    inicioPlaneacion = inicioPlaneacion.add(duracion);
    fin = inicioPlaneacion;

    // Verificar tardanza
    if (fin.isAfter(duedate)) {
      retardo = fin.difference(duedate);
    } else {
      retardo = Duration.zero;
    }

    output.add(Tuple6(job, duracion, inicio, fin, duedate, retardo));
  }
}

void sptruleadaptado() {
  // Organizar las tareas por orden de entrega
  input.sort((a, b) => a.value2.compareTo(b.value2));

  TimeOfDay timeinit = TimeOfDay.fromDateTime(input[0].value5);
  int time1InMinutes = timeinit.hour * 60 + timeinit.minute;
  int time2InMinutes = workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;

  TimeOfDay inittiemp = time1InMinutes < time2InMinutes ? workingSchedule.value1 : timeinit;

  DateTime inicioPlaneacion = DateTime(
    input[0].value5.year,
    input[0].value5.month,
    input[0].value5.day,
    inittiemp.hour,
    inittiemp.minute,
  );

  int job;
  Duration duracion;
  DateTime inicio;
  DateTime fin; 
  DateTime duedate;
  Duration retardo;
  int tiemptot;
  int findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

  for (int i = 0; i < input.length; i++) {
    var tuple = input[i];
    job = tuple.value1;
    duracion = tuple.value2;
    duedate = tuple.value3;

    // Calcular el tiempo total del día disponible
    tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + duracion.inMinutes;

    if (tiemptot > findia) {
      // Si no cabe en el día, revisar si alguna otra tarea posterior sí cabe
      for (int j = i + 1; j < input.length; j++) {
        var nextTask = input[j];
        int nextTaskDuration = nextTask.value2.inMinutes;

        // Si la siguiente tarea cabe en el tiempo restante del día
        if ((inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + nextTaskDuration <= findia) {
          // Reprogramar la siguiente tarea
          job = nextTask.value1;
          duracion = nextTask.value2;
          duedate = nextTask.value3;

          input.removeAt(j); // Quitar la tarea ya programada
          i--; // Reprocesar la tarea actual en la siguiente iteración
          break; // Salir del bucle para programar la tarea actual después
        }
      }
    }

    // Programar la tarea actual
    inicio = inicioPlaneacion;
    inicioPlaneacion = inicioPlaneacion.add(duracion);
    fin = inicioPlaneacion;

    if (fin.isAfter(duedate)) {
      retardo = fin.difference(duedate);
    } else {
      retardo = Duration.zero;
    }

    output.add(Tuple6(
      job,
      duracion,
      inicio,
      fin,
      duedate,
      retardo,
    ));
  }
}

void lptruleadaptado() {
  // Organizar las tareas por orden de entrega
  input.sort((a, b) => b.value2.compareTo(a.value2));

  TimeOfDay timeinit = TimeOfDay.fromDateTime(input[0].value5);
  int time1InMinutes = timeinit.hour * 60 + timeinit.minute;
  int time2InMinutes = workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;

  TimeOfDay inittiemp = time1InMinutes < time2InMinutes ? workingSchedule.value1 : timeinit;

  DateTime inicioPlaneacion = DateTime(
    input[0].value5.year,
    input[0].value5.month,
    input[0].value5.day,
    inittiemp.hour,
    inittiemp.minute,
  );

  int job;
  Duration duracion;
  DateTime inicio;
  DateTime fin; 
  DateTime duedate;
  Duration retardo;
  int tiemptot;
  int findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

  for (int i = 0; i < input.length; i++) {
    var tuple = input[i];
    job = tuple.value1;
    duracion = tuple.value2;
    duedate = tuple.value3;

    // Calcular el tiempo total del día disponible
    tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + duracion.inMinutes;

    if (tiemptot > findia) {
      // Si no cabe en el día, revisar si alguna otra tarea posterior sí cabe
      for (int j = i + 1; j < input.length; j++) {
        var nextTask = input[j];
        int nextTaskDuration = nextTask.value2.inMinutes;

        // Si la siguiente tarea cabe en el tiempo restante del día
        if ((inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + nextTaskDuration <= findia) {
          // Reprogramar la siguiente tarea
          job = nextTask.value1;
          duracion = nextTask.value2;
          duedate = nextTask.value3;

          input.removeAt(j); // Quitar la tarea ya programada
          i--; // Reprocesar la tarea actual en la siguiente iteración
          break; // Salir del bucle para programar la tarea actual después
        }
      }
    }

    // Programar la tarea actual
    inicio = inicioPlaneacion;
    inicioPlaneacion = inicioPlaneacion.add(duracion);
    fin = inicioPlaneacion;

    if (fin.isAfter(duedate)) {
      retardo = fin.difference(duedate);
    } else {
      retardo = Duration.zero;
    }

    output.add(Tuple6(
      job,
      duracion,
      inicio,
      fin,
      duedate,
      retardo,
    ));
  }
}

void fiforuleadaptado() {
  // Organizar las tareas por orden de entrega
  input.sort((a, b) => a.value5.compareTo(b.value5));

  TimeOfDay timeinit = TimeOfDay.fromDateTime(input[0].value5);
  int time1InMinutes = timeinit.hour * 60 + timeinit.minute;
  int time2InMinutes = workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;

  TimeOfDay inittiemp = time1InMinutes < time2InMinutes ? workingSchedule.value1 : timeinit;

  DateTime inicioPlaneacion = DateTime(
    input[0].value5.year,
    input[0].value5.month,
    input[0].value5.day,
    inittiemp.hour,
    inittiemp.minute,
  );

  int job;
  Duration duracion;
  DateTime inicio;
  DateTime fin; 
  DateTime duedate;
  Duration retardo;
  int tiemptot;
  int findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

  for (int i = 0; i < input.length; i++) {
    var tuple = input[i];
    job = tuple.value1;
    duracion = tuple.value2;
    duedate = tuple.value3;

    // Calcular el tiempo total del día disponible
    tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + duracion.inMinutes;

    if (tiemptot > findia) {
      // Si no cabe en el día, revisar si alguna otra tarea posterior sí cabe
      for (int j = i + 1; j < input.length; j++) {
        var nextTask = input[j];
        int nextTaskDuration = nextTask.value2.inMinutes;

        // Si la siguiente tarea cabe en el tiempo restante del día
        if ((inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + nextTaskDuration <= findia) {
          // Reprogramar la siguiente tarea
          job = nextTask.value1;
          duracion = nextTask.value2;
          duedate = nextTask.value3;

          input.removeAt(j); // Quitar la tarea ya programada
          i--; // Reprocesar la tarea actual en la siguiente iteración
          break; // Salir del bucle para programar la tarea actual después
        }
      }
    }

    // Programar la tarea actual
    inicio = inicioPlaneacion;
    inicioPlaneacion = inicioPlaneacion.add(duracion);
    fin = inicioPlaneacion;

    if (fin.isAfter(duedate)) {
      retardo = fin.difference(duedate);
    } else {
      retardo = Duration.zero;
    }

    output.add(Tuple6(
      job,
      duracion,
      inicio,
      fin,
      duedate,
      retardo,
    ));
  }
}
 
void wsptruleadaptado() {
  int tiemproces;
  List<double> wspt = [];

  for (var tuple in input) {
    // Paso tiempos de proceso a minutos
    tiemproces = tuple.value2.inHours * 60 + tuple.value2.inMinutes;
    wspt.add(tuple.value4 / tiemproces);
  }

  // Organizo la lista de tuplas según el indicador WSPT de mayor a menor
  for (int i = 0; i < input.length - 1; i++) {
    for (int j = 0; j < input.length - i - 1; j++) {
      if (wspt[j] < wspt[j + 1]) {
        var temp = wspt[j];
        wspt[j] = wspt[j + 1];
        wspt[j + 1] = temp;

        // Intercambiar las tareas correspondientes
        var tempTask = input[j];
        input[j] = input[j + 1];
        input[j + 1] = tempTask;
      }
    }
  }

  // Resto del código de programación
  TimeOfDay timeinit = TimeOfDay.fromDateTime(input[0].value5);
  int time1InMinutes = timeinit.hour * 60 + timeinit.minute;
  int time2InMinutes = workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;

  TimeOfDay inittiemp = time1InMinutes < time2InMinutes ? workingSchedule.value1 : timeinit;

  DateTime inicioPlaneacion = DateTime(
    input[0].value5.year,
    input[0].value5.month,
    input[0].value5.day,
    inittiemp.hour,
    inittiemp.minute,
  );

  int job;
  Duration duracion;
  DateTime inicio;
  DateTime fin; 
  DateTime duedate;
  Duration retardo;
  int tiemptot;
  int findia = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

  for (int i = 0; i < input.length; i++) {
    var tuple = input[i];
    job = tuple.value1;
    duracion = tuple.value2;
    duedate = tuple.value3;

    // Calcular el tiempo total del día disponible
    tiemptot = (inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + duracion.inMinutes;

    if (tiemptot > findia) {
      // Si no cabe en el día, revisar si alguna otra tarea posterior sí cabe
      for (int j = i + 1; j < input.length; j++) {
        var nextTask = input[j];
        int nextTaskDuration = nextTask.value2.inMinutes;

        // Si la siguiente tarea cabe en el tiempo restante del día
        if ((inicioPlaneacion.hour * 60) + inicioPlaneacion.minute + nextTaskDuration <= findia) {
          // Reprogramar la siguiente tarea
          job = nextTask.value1;
          duracion = nextTask.value2;
          duedate = nextTask.value3;

          input.removeAt(j); // Quitar la tarea ya programada
          i--; // Reprocesar la tarea actual en la siguiente iteración
          break; // Salir del bucle para programar la tarea actual después
        }
      }
    }

    // Programar la tarea actual
    inicio = inicioPlaneacion;
    inicioPlaneacion = inicioPlaneacion.add(duracion);
    fin = inicioPlaneacion;

    if (fin.isAfter(duedate)) {
      retardo = fin.difference(duedate);
    } else {
      retardo = Duration.zero;
    }

    output.add(Tuple6(
      job,
      duracion,
      inicio,
      fin,
      duedate,
      retardo,
    ));
  }
}
  
  
  
  

  ///////////////////////////////////////////////////
///////////////////Reglas DINÁMICAS////////////////////
  ///////////////////////////////////////////////////
  // Implementación de la regla de Minimum Slack
  void scheduleMinimumSlack() {
    final int workStartInMinutes = workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;
    final int workEndInMinutes = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    DateTime currentTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      workingSchedule.value1.hour,
      workingSchedule.value1.minute,
    );

    while (input.isNotEmpty) {
      List<Tuple5<int, Duration, DateTime, int, DateTime>> availableJobs = input.where((job) {
        DateTime availableDate = job.value5;
        return availableDate.isBefore(currentTime) || availableDate.isAtSameMomentAs(currentTime);
      }).toList();

      if (availableJobs.isEmpty) {
        Tuple5<int, Duration, DateTime, int, DateTime> closestJob = input.reduce((a, b) {
          return a.value5.isBefore(b.value5) ? a : b;
        });
        currentTime = closestJob.value5;
        availableJobs = [closestJob];
      }

      Tuple5<int, Duration, DateTime, int, DateTime> jobWithMinimumSlack = availableJobs.reduce((a, b) {
        return slack(a.value3, a.value2, currentTime) < slack(b.value3, b.value2, currentTime) ? a : b;
      });

      DateTime endTime = currentTime.add(jobWithMinimumSlack.value2);
      Duration delay = endTime.isAfter(jobWithMinimumSlack.value3) ? endTime.difference(jobWithMinimumSlack.value3) : Duration.zero;

      // Verificar si el tiempo de fin está fuera del horario laboral
      if (endTime.hour * 60 + endTime.minute > workEndInMinutes) {
        // Programar para el día siguiente
        currentTime = currentTime.add(Duration(days: 1));
        currentTime = DateTime(currentTime.year, currentTime.month, currentTime.day,
            workingSchedule.value1.hour, workingSchedule.value1.minute);
        endTime = currentTime.add(jobWithMinimumSlack.value2);
        delay = endTime.isAfter(jobWithMinimumSlack.value3) ? endTime.difference(jobWithMinimumSlack.value3) : Duration.zero;
      }

      output.add(Tuple6(
        jobWithMinimumSlack.value1,
        jobWithMinimumSlack.value2,
        currentTime,
        endTime,
        jobWithMinimumSlack.value3,
        delay,
      ));

      currentTime = endTime;
      input.remove(jobWithMinimumSlack);
    }
  }

  int slack(DateTime dueDate, Duration processingTime, DateTime currentTime) {
    int remainingMinutes = dueDate.difference(currentTime).inMinutes;
    return remainingMinutes - processingTime.inMinutes;
  }
  
  
  void scheduleCriticalRatio() {
    final int workStartInMinutes = workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;
    final int workEndInMinutes = workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    DateTime currentTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      workingSchedule.value1.hour,
      workingSchedule.value1.minute,
    );

    while (input.isNotEmpty) {
      // Obtener trabajos disponibles
      List<Tuple5<int, Duration, DateTime, int, DateTime>> availableJobs = input.where((job) {
        DateTime availableDate = job.value5;
        return availableDate.isBefore(currentTime) || availableDate.isAtSameMomentAs(currentTime);
      }).toList();

      // Si no hay trabajos disponibles, mover al próximo día
      if (availableJobs.isEmpty) {
        currentTime = currentTime.add(Duration(days: 1));
        currentTime = DateTime(currentTime.year, currentTime.month, currentTime.day,
            workingSchedule.value1.hour, workingSchedule.value1.minute);
        continue;
      }

      // Cálculo del CR para cada trabajo disponible
      availableJobs.sort((a, b) {
        double crA = criticalRatio(a.value2, currentTime, a.value3); // Cambiado a a.value2
        double crB = criticalRatio(b.value2, currentTime, b.value3); // Cambiado a b.value2
        return crA.compareTo(crB);
      });

      // Seleccionar el trabajo con el menor CR
      Tuple5<int, Duration, DateTime, int, DateTime> jobWithCriticalRatio = availableJobs.first;

      DateTime endTime = currentTime.add(jobWithCriticalRatio.value2);
      Duration delay = endTime.isAfter(jobWithCriticalRatio.value3) ? endTime.difference(jobWithCriticalRatio.value3) : Duration.zero;

      // Verificar si el tiempo de fin está fuera del horario laboral
      if (endTime.hour * 60 + endTime.minute > workEndInMinutes) {
        // Si se sale del horario, programar para el día siguiente
        currentTime = currentTime.add(Duration(days: 1));
        currentTime = DateTime(currentTime.year, currentTime.month, currentTime.day,
            workingSchedule.value1.hour, workingSchedule.value1.minute);
        endTime = currentTime.add(jobWithCriticalRatio.value2);
        delay = endTime.isAfter(jobWithCriticalRatio.value3) ? endTime.difference(jobWithCriticalRatio.value3) : Duration.zero;
      }

      output.add(Tuple6(
        jobWithCriticalRatio.value1,
        jobWithCriticalRatio.value2,
        currentTime,
        endTime,
        jobWithCriticalRatio.value3,
        delay,
      ));

      // Actualizar el tiempo actual y eliminar el trabajo programado
      currentTime = endTime;
      input.remove(jobWithCriticalRatio);
    }
  }

  double criticalRatio(Duration processingTime, DateTime currentTime, DateTime dueDate) {
    int remainingMinutes = dueDate.difference(currentTime).inMinutes;
    return remainingMinutes / processingTime.inMinutes;
  }


  
  
  
  
  
  
  
  
  

 
}
