/// Parametros configurables del algoritmo genetico (GENETICS) de todos los
/// ambientes. Vive en entities/ porque cruza todas las capas: se construye
/// en presentation (GeneticParamsDialog) y se consume en
/// services/scheduling/genetic_engine.dart. Los valores por defecto son los
/// que antes estaban fijos; ver docs/diagnostico_genetics.md.
import 'package:production_planning/entities/schedule_objective.dart';

class GeneticParams {
  /// Individuos por generacion.
  final int populationSize;

  /// Limite de generaciones.
  final int maxGenerations;

  /// Se detiene si el mejor no mejora en este numero de generaciones.
  final int stallGenerations;

  /// Individuos que compiten en cada torneo de seleccion.
  final int tournamentSize;

  /// Probabilidad de cruzar dos padres (0-1).
  final double crossoverRate;

  /// Probabilidad de mutar un hijo (0-1).
  final double mutationRate;

  /// Mejores individuos que pasan sin cambios a la siguiente generacion.
  final int elitism;

  /// Semilla del generador aleatorio: misma semilla, mismo resultado.
  final int seed;

  /// Funcion objetivo que minimiza el algoritmo.
  final ScheduleObjective objective;

  const GeneticParams({
    this.populationSize = 30,
    this.maxGenerations = 60,
    this.stallGenerations = 15,
    this.tournamentSize = 3,
    this.crossoverRate = 0.8,
    this.mutationRate = 0.1,
    this.elitism = 2,
    this.seed = 20261016,
    this.objective = ScheduleObjective.makespan,
  });

  GeneticParams copyWith({
    int? populationSize,
    int? maxGenerations,
    int? stallGenerations,
    int? tournamentSize,
    double? crossoverRate,
    double? mutationRate,
    int? elitism,
    int? seed,
    ScheduleObjective? objective,
  }) {
    return GeneticParams(
      populationSize: populationSize ?? this.populationSize,
      maxGenerations: maxGenerations ?? this.maxGenerations,
      stallGenerations: stallGenerations ?? this.stallGenerations,
      tournamentSize: tournamentSize ?? this.tournamentSize,
      crossoverRate: crossoverRate ?? this.crossoverRate,
      mutationRate: mutationRate ?? this.mutationRate,
      elitism: elitism ?? this.elitism,
      seed: seed ?? this.seed,
      objective: objective ?? this.objective,
    );
  }

  /// Para el payload de los isolates (solo tipos primitivos).
  Map<String, dynamic> toMap() => {
        'populationSize': populationSize,
        'maxGenerations': maxGenerations,
        'stallGenerations': stallGenerations,
        'tournamentSize': tournamentSize,
        'crossoverRate': crossoverRate,
        'mutationRate': mutationRate,
        'elitism': elitism,
        'seed': seed,
        'objective': objective.name,
      };

  /// Inverso de [toMap]; null da los valores por defecto.
  factory GeneticParams.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const GeneticParams();
    return GeneticParams(
      populationSize: map['populationSize'] as int,
      maxGenerations: map['maxGenerations'] as int,
      stallGenerations: map['stallGenerations'] as int,
      tournamentSize: map['tournamentSize'] as int,
      crossoverRate: (map['crossoverRate'] as num).toDouble(),
      mutationRate: (map['mutationRate'] as num).toDouble(),
      elitism: map['elitism'] as int,
      seed: map['seed'] as int,
      objective: ScheduleObjective.values.byName(map['objective'] as String),
    );
  }

  @override
  String toString() =>
      'GeneticParams(pop: $populationSize, gen: $maxGenerations, '
      'stall: $stallGenerations, k: $tournamentSize, '
      'pc: $crossoverRate, pm: $mutationRate, elite: $elitism, '
      'seed: $seed, objetivo: ${objective.label})';
}
