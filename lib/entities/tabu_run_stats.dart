import 'package:production_planning/entities/tabu_objective.dart';

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

  /// Funcion objetivo con la que se corrio la busqueda. Define el nombre y
  /// la unidad de [initialValue] y [bestValue].
  final TabuObjective objective;

  /// Valor de [objective] en el punto de partida de la busqueda
  /// (minutos, o trabajos para [TabuObjective.tardyJobs]).
  final int initialValue;

  /// Mejor valor de [objective] encontrado.
  final int bestValue;

  /// true si la busqueda paro por el limite de tiempo antes de agotar las
  /// iteraciones; false si llego a [maxIterations].
  final bool stoppedByTime;

  const TabuRunStats({
    required this.iterations,
    required this.maxIterations,
    required this.elapsedMs,
    required this.timeBudgetMs,
    required this.objective,
    required this.initialValue,
    required this.bestValue,
    required this.stoppedByTime,
  });

  /// Mejora de [objective] respecto al punto de partida, en porcentaje.
  double get improvementPercent => initialValue == 0
      ? 0.0
      : (initialValue - bestValue) * 100 / initialValue;

  /// Costo promedio de una iteracion, en milisegundos.
  int get msPerIteration =>
      iterations == 0 ? elapsedMs : (elapsedMs / iterations).round();

  @override
  String toString() =>
      'TabuRunStats(iter: $iterations/$maxIterations, ${elapsedMs}ms/'
      '${timeBudgetMs}ms, ${objective.label}: $initialValue→$bestValue '
      '${objective.unit}, '
      'stoppedByTime: $stoppedByTime)';
}