/// Funcion objetivo que minimiza una metaheuristica (busqueda tabu o
/// algoritmo genetico). Vive en entities/ porque se elige en presentation y
/// se evalua en services/algorithms. Notacion de Pinedo (2016).
enum ScheduleObjective {
  totalFlow('Flujo total', 'Σ (Cj − rj)', 'min'),
  makespan('Makespan', 'Cmax', 'min'),
  totalTardiness('Tardanza total', 'Σ Tj', 'min'),
  tardyJobs('Trabajos retrasados', 'Σ Uj', 'trabajos'),
  totalEarliness('Anticipo total', 'Σ Ej', 'min');

  final String label;
  final String formula;
  final String unit;

  const ScheduleObjective(this.label, this.formula, this.unit);
}
