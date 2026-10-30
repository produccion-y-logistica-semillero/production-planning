// lib/services/scheduling/genetic_engine.dart
//
// Generational genetic algorithm shared by the shop environments (Holland,
// 1975; Goldberg, 1989): a population of chromosomes, tournament selection,
// crossover, mutation and elitism, stopping after a number of generations or
// once the best solution has not improved for a while.
//
// Each environment supplies its own encoding and operators — an operation
// permutation (Bierwirth, 1995) with a machine-assignment vector for the
// flexible shops (Pezzella, Morganti & Ciaschetti, 2008), or a job
// permutation for the flexible flow shop (Ruiz & Maroto, 2006) — and a
// decoder that turns a chromosome into a schedule with the platform's own
// dispatching loop and preemption engine, so what the GA evaluates is
// exactly what gets scheduled. The random generator is seeded: the same
// order with the same settings always yields the same schedule.

import 'dart:math';

/// Fixed settings of the genetic algorithm. Documented in
/// docs/diagnostico_genetics.md.
class GeneticSettings {
  final int populationSize;
  final int maxGenerations;

  /// Stop once the best fitness has not improved for this many generations.
  final int stallGenerations;
  final int tournamentSize;
  final double crossoverRate;
  final double mutationRate;

  /// Best individuals copied unchanged into the next generation.
  final int elitism;
  final int seed;

  const GeneticSettings({
    this.populationSize = 30,
    this.maxGenerations = 60,
    this.stallGenerations = 15,
    this.tournamentSize = 3,
    this.crossoverRate = 0.8,
    this.mutationRate = 0.1,
    this.elitism = 2,
    this.seed = 20261016,
  });
}

class GeneticResult<C> {
  final C best;
  final double bestFitness;
  final int generations;

  const GeneticResult(this.best, this.bestFitness, this.generations);
}

/// Runs the GA and returns the best chromosome found (lower fitness is
/// better). [seeds] are included in the first generation (e.g. chromosomes
/// built from dispatching rules); the rest is filled with [randomIndividual].
/// [key] identifies equal chromosomes so their fitness is computed once.
GeneticResult<C> runGenetic<C>({
  required List<C> seeds,
  required C Function(Random random) randomIndividual,
  required double Function(C chromosome) fitness,
  required C Function(C a, C b, Random random) crossover,
  required C Function(C chromosome, Random random) mutate,
  required String Function(C chromosome) key,
  GeneticSettings settings = const GeneticSettings(),
}) {
  final random = Random(settings.seed);
  final cache = <String, double>{};
  double eval(C c) => cache.putIfAbsent(key(c), () => fitness(c));

  var population = <C>[
    ...seeds.take(settings.populationSize),
  ];
  while (population.length < settings.populationSize) {
    population.add(randomIndividual(random));
  }

  // Sorted best-first; ties keep insertion order (List.sort is not stable,
  // so the index settles them and runs are reproducible).
  List<C> ranked(List<C> pop) {
    final indexed = List<int>.generate(pop.length, (i) => i)
      ..sort((a, b) {
        final c = eval(pop[a]).compareTo(eval(pop[b]));
        return c != 0 ? c : a.compareTo(b);
      });
    return [for (final i in indexed) pop[i]];
  }

  population = ranked(population);
  C best = population.first;
  double bestFitness = eval(best);
  int stall = 0;
  int generation = 0;

  C tournament() {
    C? winner;
    for (int i = 0; i < settings.tournamentSize; i++) {
      final candidate = population[random.nextInt(population.length)];
      if (winner == null || eval(candidate) < eval(winner)) winner = candidate;
    }
    return winner as C;
  }

  while (generation < settings.maxGenerations &&
      stall < settings.stallGenerations) {
    generation++;
    final next = <C>[
      ...population.take(min(settings.elitism, population.length)),
    ];
    while (next.length < settings.populationSize) {
      final a = tournament();
      final b = tournament();
      C child = random.nextDouble() < settings.crossoverRate
          ? crossover(a, b, random)
          : a;
      if (random.nextDouble() < settings.mutationRate) {
        child = mutate(child, random);
      }
      next.add(child);
    }
    population = ranked(next);
    final f = eval(population.first);
    if (f < bestFitness) {
      best = population.first;
      bestFitness = f;
      stall = 0;
    } else {
      stall++;
    }
  }
  return GeneticResult(best, bestFitness, generation);
}

// ---------------------------------------------------------------------------
// Operation-based chromosome (job shop, open shop, recurrent and flexible
// variants): a priority permutation of the operations plus, for each
// operation, the index of the machine it is assigned to among its eligible
// machines.
// ---------------------------------------------------------------------------

class OperationChromosome {
  /// Permutation of operation indexes: earlier = higher priority.
  final List<int> order;

  /// Indexed by operation: index into that operation's eligible machines.
  final List<int> machineChoice;

  const OperationChromosome(this.order, this.machineChoice);

  String get key => '${order.join(',')}|${machineChoice.join(',')}';
}

/// Precedence-preserving order crossover (POX; Bierwirth, Mattfeld &
/// Kopfer, 1996): the operations of a random subset of jobs keep their
/// positions from parent [a]; the remaining positions are filled with the
/// other operations in the order they appear in [b]. Machine genes are
/// crossed uniformly.
OperationChromosome poxCrossover(
  OperationChromosome a,
  OperationChromosome b,
  List<int> jobOfOperation,
  Random random,
) {
  final jobs = jobOfOperation.toSet().toList()..sort();
  final keep = <int>{for (final j in jobs) if (random.nextBool()) j};
  final child = List<int?>.filled(a.order.length, null);
  for (int i = 0; i < a.order.length; i++) {
    if (keep.contains(jobOfOperation[a.order[i]])) child[i] = a.order[i];
  }
  final fill = b.order.where((op) => !keep.contains(jobOfOperation[op]));
  final it = fill.iterator;
  for (int i = 0; i < child.length; i++) {
    if (child[i] == null && it.moveNext()) child[i] = it.current;
  }
  final machines = List<int>.generate(
    a.machineChoice.length,
    (op) => random.nextBool() ? a.machineChoice[op] : b.machineChoice[op],
  );
  return OperationChromosome(child.cast<int>(), machines);
}

/// Swap mutation on the order and, for one random operation with several
/// eligible machines, a machine reassignment.
OperationChromosome operationMutation(
  OperationChromosome c,
  List<int> machineCount,
  Random random,
) {
  final order = List<int>.of(c.order);
  if (order.length > 1) {
    final i = random.nextInt(order.length);
    final j = random.nextInt(order.length);
    final t = order[i];
    order[i] = order[j];
    order[j] = t;
  }
  final machines = List<int>.of(c.machineChoice);
  final flexible = [
    for (int op = 0; op < machineCount.length; op++)
      if (machineCount[op] > 1) op
  ];
  if (flexible.isNotEmpty) {
    final op = flexible[random.nextInt(flexible.length)];
    machines[op] = random.nextInt(machineCount[op]);
  }
  return OperationChromosome(order, machines);
}

OperationChromosome randomOperationChromosome(
  List<int> machineCount,
  Random random,
) {
  final order = List<int>.generate(machineCount.length, (i) => i)
    ..shuffle(random);
  final machines = [for (final n in machineCount) random.nextInt(max(n, 1))];
  return OperationChromosome(order, machines);
}

// ---------------------------------------------------------------------------
// Job permutation (flexible flow shop).
// ---------------------------------------------------------------------------

/// Order crossover (OX; Davis, 1985) on a permutation.
List<int> orderCrossover(List<int> a, List<int> b, Random random) {
  final n = a.length;
  if (n < 2) return List<int>.of(a);
  int i = random.nextInt(n);
  int j = random.nextInt(n);
  if (i > j) {
    final t = i;
    i = j;
    j = t;
  }
  final child = List<int?>.filled(n, null);
  final taken = <int>{};
  for (int k = i; k <= j; k++) {
    child[k] = a[k];
    taken.add(a[k]);
  }
  final rest = b.where((x) => !taken.contains(x)).iterator;
  for (int k = 0; k < n; k++) {
    if (child[k] == null && rest.moveNext()) child[k] = rest.current;
  }
  return child.cast<int>();
}

/// Insertion (shift) mutation: one element moves to another position.
List<int> insertionMutation(List<int> p, Random random) {
  final out = List<int>.of(p);
  if (out.length < 2) return out;
  final from = random.nextInt(out.length);
  final value = out.removeAt(from);
  out.insert(random.nextInt(out.length + 1), value);
  return out;
}
