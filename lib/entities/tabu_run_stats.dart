/// Resumen de UNA corrida de la busqueda tabu para maquinas paralelas.
/// Vive en entities/ junto a [TabuParams]: lo escribe services/algorithms,
/// viaja dentro de [Metrics] y lo lee presentation.
///
/// Sirve para diagnosticar el cuello de botella: si la busqueda se detuvo
/// por tiempo y no por iteraciones, subir el presupuesto de tiempo (o bajar
/// el costo por iteracion) puede mejorar el resultado.
class TabuRunStats {
  /// Iteraciones realizadas (incluye las que no encontraron candidato).
  final int iterations;

  /// Limite de iteraciones efectivo (ya acotado, no el valor crudo de la UI).
  final int maxIterations;

  /// Tiempo total de la corrida, en milisegundos.
  final int elapsedMs;

  /// Presupuesto de tiempo efectivo, en milisegundos.
  final int timeBudgetMs;

  /// Flujo total (minutos) del punto de partida de la busqueda.
  final int initialFlowMinutes;

  /// Mejor flujo total (minutos) encontrado.
  final int bestFlowMinutes;

  /// true si la busqueda paro por el limite de tiempo antes de agotar las
  /// iteraciones; false si llego a [maxIterations].
  final bool stoppedByTime;

  const TabuRunStats({
    required this.iterations,
    required this.maxIterations,
    required this.elapsedMs,
    required this.timeBudgetMs,
    required this.initialFlowMinutes,
    required this.bestFlowMinutes,
    required this.stoppedByTime,
  });

  /// Mejora del flujo total respecto al punto de partida, en porcentaje.
  double get improvementPercent => initialFlowMinutes == 0
      ? 0.0
      : (initialFlowMinutes - bestFlowMinutes) * 100 / initialFlowMinutes;

  /// Costo promedio de una iteracion, en milisegundos.
  int get msPerIteration =>
      iterations == 0 ? elapsedMs : (elapsedMs / iterations).round();

  @override
  String toString() =>
      'TabuRunStats(iter: $iterations/$maxIterations, ${elapsedMs}ms/'
      '${timeBudgetMs}ms, flujo: $initialFlowMinutes→$bestFlowMinutes, '
      'stoppedByTime: $stoppedByTime)';
}