/// Parametros configurables de la busqueda tabu para maquinas paralelas.
/// Vive en entities/ porque cruza todas las capas: se construye en
/// presentation y se consume en services/algorithms.
class TabuParams {

  final int maxIterations;

  final int intraAttempts;

  final int interJobSamples;

  final int maxDestinations;

  final int timeBudgetMs;

  final int seed;

  final bool randomStart;

  const TabuParams({
    this.maxIterations = 1000,
    this.intraAttempts = 40,
    this.interJobSamples = 10,
    this.maxDestinations = 3,
    this.timeBudgetMs = 4000,
    this.seed = 20260806,
    this.randomStart = false,
  });

  TabuParams copyWith({
    int? maxIterations,
    int? intraAttempts,
    int? interJobSamples,
    int? maxDestinations,
    int? timeBudgetMs,
    int? seed,
    bool? randomStart,
  }) {
    return TabuParams(
      maxIterations: maxIterations ?? this.maxIterations,
      intraAttempts: intraAttempts ?? this.intraAttempts,
      interJobSamples: interJobSamples ?? this.interJobSamples,
      maxDestinations: maxDestinations ?? this.maxDestinations,
      timeBudgetMs: timeBudgetMs ?? this.timeBudgetMs,
      seed: seed ?? this.seed,
      randomStart: randomStart ?? this.randomStart,
    );
  }

  @override
    String toString() =>
      'TabuParams(iter: $maxIterations, intra: $intraAttempts, '
      'inter: $interJobSamples, dest: $maxDestinations, '
      'budget: ${timeBudgetMs}ms, randomStart: $randomStart)';
}