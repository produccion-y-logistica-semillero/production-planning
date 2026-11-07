enum TabuObjective {
  totalFlow('Flujo total', 'Σ (Cj − rj)', 'min'),
  makespan('Makespan', 'Cmax', 'min'),
  totalTardiness('Tardanza total', 'Σ Tj', 'min'),
  tardyJobs('Trabajos retrasados', 'Σ Uj', 'trabajos');
  //hola('Holaaaa', 'Ser feliz', 'Max') ;

  final String label;
  final String formula;
  final String unit;

  const TabuObjective(this.label, this.formula, this.unit);
}