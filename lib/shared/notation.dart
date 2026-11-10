// lib/shared/notation.dart
//
// Theoretical scheduling notation shown alongside the app's plain-language
// labels, following Pinedo, M. L. (2016). Scheduling: Theory, Algorithms,
// and Systems (5th ed.), ch. 2 (α | β | γ, data and objectives) and the
// chapters of each rule. Three ways to see it, all from this one catalog:
//   * a global switch ("Notación teórica" in the side menu) that adds the
//     symbols to the screens ([showNotation]);
//   * a Σ button on each screen with the notation of that screen
//     ([NotationButton]);
//   * a glossary page with everything (NotationGlossaryPage).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:production_planning/shared/motion/motion.dart';

/// Global switch: when true, the screens add the theoretical symbols next
/// to their labels. Read at start-up from [notationFileName] (main.dart).
final ValueNotifier<bool> showNotation = ValueNotifier(false);

/// File in the app-support folder that persists the switch.
const String notationFileName = 'notation.txt';

/// Turns the global switch on or off and remembers it for the next start.
Future<void> setNotation(bool on) async {
  showNotation.value = on;
  try {
    final dir = await getApplicationSupportDirectory();
    await File('${dir.path}/$notationFileName').writeAsString(on ? '1' : '0');
  } catch (_) {
    // Not persisted (e.g. in tests): the switch still applies this session.
  }
}

/// Glossary section.
enum NotationSection {
  environment('Ambiente de máquinas (α)'),
  constraints('Restricciones (β)'),
  data('Datos del problema'),
  objectives('Funciones objetivo (γ)'),
  rules('Reglas y algoritmos');

  final String title;
  const NotationSection(this.title);
}

/// Screen where an entry is relevant (its Σ button lists it).
enum NotationContext { machines, routes, orders, picker, metrics }

class NotationEntry {
  /// Symbol as written in the literature ("pij", "Cmax", "Fm").
  final String symbol;

  /// What the app calls it.
  final String name;
  final String definition;

  /// Formula, when there is one.
  final String? formula;
  final NotationSection section;
  final Set<NotationContext> contexts;

  /// Rule code in the database, for rule entries ("EDD", "MS").
  final String? ruleCode;

  const NotationEntry({
    required this.symbol,
    required this.name,
    required this.definition,
    required this.section,
    this.formula,
    this.contexts = const {},
    this.ruleCode,
  });
}

const String notationReference =
    'Pinedo, M. L. (2016). Scheduling: Theory, Algorithms, and Systems '
    '(5.ª ed.). Springer.';

const _m = NotationContext.machines;
const _r = NotationContext.routes;
const _o = NotationContext.orders;
const _p = NotationContext.picker;
const _k = NotationContext.metrics;

const List<NotationEntry> kNotation = [
  // ── α: ambiente ──────────────────────────────────────────────────────────
  NotationEntry(
    symbol: 'α | β | γ',
    name: 'Notación de tres campos',
    definition: 'Forma estándar de describir un problema de programación: '
        'α es el ambiente de máquinas, β las restricciones y características '
        'de los trabajos, y γ la función objetivo a minimizar. Ejemplo: '
        'Fm | rj, sjk | ΣTj.',
    section: NotationSection.environment,
    contexts: {_p, _k},
  ),
  NotationEntry(
    symbol: '1',
    name: 'Una máquina (Single Machine)',
    definition: 'Todos los trabajos pasan por una única máquina.',
    section: NotationSection.environment,
    contexts: {_m, _p},
  ),
  NotationEntry(
    symbol: 'Pm / Qm / Rm',
    name: 'Máquinas paralelas',
    definition: 'Una estación con m máquinas; cada trabajo usa una sola. Pm: '
        'idénticas; Qm: con velocidades distintas; Rm: no relacionadas '
        '(el tiempo depende de la pareja máquina-trabajo, pij). En la '
        'plataforma cada máquina puede tener su propio tiempo, así que el '
        'caso general es Rm.',
    section: NotationSection.environment,
    contexts: {_m, _p},
  ),
  NotationEntry(
    symbol: 'Fm',
    name: 'Flow Shop',
    definition: 'm máquinas en serie; todos los trabajos siguen la misma '
        'ruta. La plataforma programa una permutación (todos en el mismo '
        'orden en cada máquina).',
    section: NotationSection.environment,
    contexts: {_r, _p},
  ),
  NotationEntry(
    symbol: 'FFc',
    name: 'Flow Shop flexible (híbrido)',
    definition: 'c etapas en serie, cada una con varias máquinas en '
        'paralelo; el trabajo usa una máquina por etapa.',
    section: NotationSection.environment,
    contexts: {_r, _p},
  ),
  NotationEntry(
    symbol: 'Jm',
    name: 'Job Shop',
    definition: 'm máquinas; cada trabajo tiene su propia ruta '
        '(orden de máquinas).',
    section: NotationSection.environment,
    contexts: {_r, _p},
  ),
  NotationEntry(
    symbol: 'FJc',
    name: 'Job Shop flexible',
    definition: 'c centros de trabajo (estaciones) con máquinas en paralelo; '
        'cada trabajo tiene su ruta y en cada centro se elige la máquina.',
    section: NotationSection.environment,
    contexts: {_r, _p},
  ),
  NotationEntry(
    symbol: 'Om',
    name: 'Open Shop',
    definition: 'Cada trabajo debe pasar por varias máquinas, pero el orden '
        'no está fijado: el programa también lo decide. Con varias máquinas '
        'por estación la plataforma lo llama Open Shop flexible.',
    section: NotationSection.environment,
    contexts: {_r, _p},
  ),
  // ── β: restricciones ─────────────────────────────────────────────────────
  NotationEntry(
    symbol: 'rj',
    name: 'Fecha de liberación (release, disponibilidad)',
    definition: 'Momento desde el que el trabajo j puede empezar.',
    section: NotationSection.constraints,
    contexts: {_o, _p},
  ),
  NotationEntry(
    symbol: 'sjk',
    name: 'Alistamiento dependiente de la secuencia',
    definition: 'Tiempo de preparación de la máquina al pasar del trabajo j '
        'al trabajo k. En la plataforma depende del estado (A-J) que deja '
        'un trabajo y del que necesita el siguiente (matriz de alistamiento).',
    section: NotationSection.constraints,
    contexts: {_o, _m, _p},
  ),
  NotationEntry(
    symbol: 'prmp',
    name: 'Interrupción (preemption)',
    definition: 'Una operación puede partirse y retomarse después. En la '
        'plataforma se usa cuando una tarea se marca como interrumpible y la '
        'corta el fin del turno, un descanso o un mantenimiento.',
    section: NotationSection.constraints,
    contexts: {_o, _m, _p},
  ),
  NotationEntry(
    symbol: 'brkdwn',
    name: 'Indisponibilidad de máquinas',
    definition: 'Periodos en que una máquina no puede trabajar: turno, '
        'mantenimientos programados y descansos tras uso continuo.',
    section: NotationSection.constraints,
    contexts: {_m, _p},
  ),
  NotationEntry(
    symbol: 'prec',
    name: 'Precedencias',
    definition: 'Una operación no puede empezar antes de que terminen sus '
        'predecesoras (las flechas de la ruta de proceso).',
    section: NotationSection.constraints,
    contexts: {_r, _p},
  ),
  NotationEntry(
    symbol: 'recrc',
    name: 'Recirculación',
    definition: 'Un trabajo puede visitar la misma máquina más de una vez '
        '(ambiente Recurrente).',
    section: NotationSection.constraints,
    contexts: {_r, _p},
  ),
  // ── Datos ─────────────────────────────────────────────────────────────────
  NotationEntry(
    symbol: 'i (Mi)',
    name: 'Máquina',
    definition: 'En la literatura las máquinas se indexan con i y se '
        'escriben Mi (i = 1, …, m). En la plataforma, una estación de '
        'trabajo agrupa máquinas del mismo tipo (una etapa o centro de '
        'trabajo).',
    section: NotationSection.data,
    contexts: {_m, _r},
  ),
  NotationEntry(
    symbol: 'j',
    name: 'Trabajo (job)',
    definition: 'Cada trabajo j = 1, …, n del programa de producción.',
    section: NotationSection.data,
    contexts: {_o},
  ),
  NotationEntry(
    symbol: '(i, j)',
    name: 'Operación',
    definition: 'El paso del trabajo j por la máquina i (una tarea de la '
        'ruta de proceso).',
    section: NotationSection.data,
    contexts: {_r, _o},
  ),
  NotationEntry(
    symbol: 'pij',
    name: 'Tiempo de proceso',
    definition: 'Duración de la operación del trabajo j en la máquina i '
        '(pj si hay una sola máquina).',
    section: NotationSection.data,
    contexts: {_o, _m},
  ),
  NotationEntry(
    symbol: 'dj',
    name: 'Fecha de entrega (due date)',
    definition: 'Momento comprometido para terminar el trabajo j.',
    section: NotationSection.data,
    contexts: {_o},
  ),
  NotationEntry(
    symbol: 'wj',
    name: 'Peso (prioridad)',
    definition: 'Importancia relativa del trabajo j; en la plataforma es la '
        'prioridad del trabajo.',
    section: NotationSection.data,
    contexts: {_o},
  ),
  NotationEntry(
    symbol: 'Cj',
    name: 'Fecha de terminación',
    definition: 'Momento en que el trabajo j termina su última operación '
        '(Cij para la operación en la máquina i).',
    section: NotationSection.data,
    contexts: {_k},
  ),
  NotationEntry(
    symbol: 'Lj',
    name: 'Retraso con signo (lateness)',
    definition: 'Positivo si termina tarde, negativo si termina antes.',
    formula: 'Lj = Cj − dj',
    section: NotationSection.data,
    contexts: {_k},
  ),
  NotationEntry(
    symbol: 'Tj',
    name: 'Tardanza (tardiness)',
    definition: 'Cuánto tarde termina el trabajo; 0 si llega a tiempo.',
    formula: 'Tj = max(Cj − dj, 0)',
    section: NotationSection.data,
    contexts: {_k},
  ),
  NotationEntry(
    symbol: 'Ej',
    name: 'Anticipo (earliness)',
    definition: 'Cuánto antes de su entrega termina el trabajo; 0 si llega '
        'tarde.',
    formula: 'Ej = max(dj − Cj, 0)',
    section: NotationSection.data,
    contexts: {_k},
  ),
  NotationEntry(
    symbol: 'Uj',
    name: 'Trabajo retrasado',
    definition: 'Indicador: 1 si el trabajo termina después de su entrega.',
    formula: 'Uj = 1 si Cj > dj; 0 si no',
    section: NotationSection.data,
    contexts: {_k},
  ),
  // ── γ: objetivos ─────────────────────────────────────────────────────────
  NotationEntry(
    symbol: 'Cmax',
    name: 'Makespan',
    definition: 'Duración total del programa: termina el último trabajo.',
    formula: 'Cmax = max(C1, …, Cn)',
    section: NotationSection.objectives,
    contexts: {_k, _p},
  ),
  NotationEntry(
    symbol: 'Σ(Cj − rj)',
    name: 'Flujo total',
    definition: 'Suma del tiempo que cada trabajo pasa en el sistema.',
    formula: 'ΣFj = Σ (Cj − rj)',
    section: NotationSection.objectives,
    contexts: {_k, _p},
  ),
  NotationEntry(
    symbol: 'ΣTj',
    name: 'Tardanza total',
    definition: 'Suma de las tardanzas.',
    formula: 'ΣTj = Σ max(Cj − dj, 0)',
    section: NotationSection.objectives,
    contexts: {_k, _p},
  ),
  NotationEntry(
    symbol: 'ΣwjTj',
    name: 'Tardanza ponderada',
    definition: 'Tardanza total pesando cada trabajo por su prioridad.',
    formula: 'ΣwjTj',
    section: NotationSection.objectives,
    contexts: {_k},
  ),
  NotationEntry(
    symbol: 'ΣUj',
    name: 'Trabajos retrasados',
    definition: 'Número de trabajos que terminan después de su entrega.',
    formula: 'ΣUj',
    section: NotationSection.objectives,
    contexts: {_k, _p},
  ),
  NotationEntry(
    symbol: 'ΣEj',
    name: 'Anticipo total',
    definition: 'Suma de los anticipos; terminar muy antes es inventario en '
        'espera (enfoque justo a tiempo).',
    formula: 'ΣEj = Σ max(dj − Cj, 0)',
    section: NotationSection.objectives,
    contexts: {_k, _p},
  ),
  NotationEntry(
    symbol: 'Tmax',
    name: 'Tardanza máxima',
    definition: 'El mayor retraso de un solo trabajo; 0 si todos llegan a '
        'tiempo.',
    formula: 'Tmax = max Tj',
    section: NotationSection.objectives,
    contexts: {_k},
  ),
  NotationEntry(
    symbol: 'Lmax',
    name: 'Retraso máximo',
    definition: 'El mayor retraso con signo entre los trabajos. Puede ser '
        'negativo: indica el margen del trabajo más ajustado.',
    formula: 'Lmax = max Lj',
    section: NotationSection.objectives,
    contexts: {_k},
  ),
  // ── Reglas y algoritmos ──────────────────────────────────────────────────
  NotationEntry(
    symbol: 'FIFO',
    name: 'Primero en llegar, primero en ser atendido',
    definition: 'Atiende primero al trabajo liberado antes.',
    formula: 'min rj',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'FIFO',
  ),
  NotationEntry(
    symbol: 'SPT / LPT',
    name: 'Tiempo de proceso más corto / más largo',
    definition: 'SPT minimiza ΣCj en 1 || ΣCj; LPT reparte carga en '
        'paralelas (Pm || Cmax).',
    formula: 'SPT: min pj ; LPT: max pj',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'SPT',
  ),
  NotationEntry(
    symbol: 'EDD',
    name: 'Fecha de entrega más próxima',
    definition: 'Óptima para 1 || Lmax.',
    formula: 'min dj',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'EDD',
  ),
  NotationEntry(
    symbol: 'WSPT',
    name: 'Tiempo de proceso ponderado más corto',
    definition: 'Regla de Smith; óptima para 1 || ΣwjCj.',
    formula: 'max wj / pj',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'WSPT',
  ),
  NotationEntry(
    symbol: 'MS',
    name: 'Holgura mínima (Minimum Slack)',
    definition: 'Atiende primero al trabajo con menos margen en el instante '
        't de la decisión.',
    formula: 'min  max(dj − pj − t, 0)   (pj: trabajo que le falta)',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'MS',
  ),
  NotationEntry(
    symbol: 'CR',
    name: 'Razón crítica',
    definition: 'Tiempo hasta la entrega por unidad de trabajo pendiente.',
    formula: 'min  (dj − t) / pj',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'CR',
  ),
  NotationEntry(
    symbol: 'ATCS',
    name: 'Apparent Tardiness Cost with Setups',
    definition: 'Índice de Lee, Bhaskaran y Pinedo (1997) para '
        '1 | sjk | ΣwjTj; K1 y K2 se calibran con la instancia.',
    formula: 'max  Ij(t, l) = (wj/pj) · exp(−max(dj − pj − t, 0) / (K1·p̄)) '
        '· exp(−slj / (K2·s̄))',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'ATCS',
  ),
  NotationEntry(
    symbol: 'LWR / MWR',
    name: 'Menor / mayor trabajo restante',
    definition: 'Comparan el tiempo de proceso que le falta a cada trabajo '
        'en su ruta.',
    formula: 'LWR: min Σ pij restantes ; MWR: max Σ pij restantes',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'LWR',
  ),
  NotationEntry(
    symbol: '*_ADAPTADO',
    name: 'Versión dinámica de una regla',
    definition: 'Evalúa el mismo índice en cada instante t en que se libera '
        'una máquina, solo entre los trabajos disponibles, con el tiempo '
        'real (pij + sjk e interrupciones).',
    section: NotationSection.rules,
    contexts: {_p},
  ),
  NotationEntry(
    symbol: 'Johnson',
    name: 'Regla de Johnson (1954)',
    definition: 'Óptima para F2 || Cmax. Conjunto I: trabajos con '
        'p1j ≤ p2j, en orden creciente de p1j; luego conjunto II: '
        'p1j > p2j, en orden decreciente de p2j.',
    formula: 'π = (I ↑ p1j , II ↓ p2j)',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'JOHNSON',
  ),
  NotationEntry(
    symbol: 'CDS',
    name: 'Campbell, Dudek y Smith (1970)',
    definition: 'Heurística para Fm || Cmax: crea m − 1 problemas de dos '
        'máquinas ficticias, aplica Johnson a cada uno y se queda con la '
        'secuencia de menor Cmax.',
    formula: "k = 1…m−1:  p'1j = Σ(i=1..k) pij ,  p'2j = Σ(i=m−k+1..m) pij",
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'CDS',
  ),
  NotationEntry(
    symbol: 'PC',
    name: 'Prioridad compuesta',
    definition: 'Combina urgencia y prioridad por minuto en un puntaje.',
    formula: 'max  1/CRj + wj/pj',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'PRIORIDAD_COMPUESTA',
  ),
  NotationEntry(
    symbol: 'GA',
    name: 'Algoritmo genético',
    definition: 'Población de secuencias π; selección por torneo de tamaño '
        'k, cruce con probabilidad pc (OX / POX), mutación con '
        'probabilidad pm, elitismo e; se detiene tras G generaciones o sin '
        'mejora. Minimiza la función objetivo γ elegida.',
    formula: 'min f(π),  f ∈ {Cmax, Σ(Cj − rj), ΣTj, ΣUj, ΣEj}',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'GENETICS',
  ),
  NotationEntry(
    symbol: 'TS',
    name: 'Búsqueda tabú',
    definition: 'Desde π0 explora el vecindario N(π); prohíbe por L '
        'iteraciones los movimientos recientes (lista tabú) salvo que '
        'mejoren la mejor solución (aspiración).',
    formula: 'π(k+1) = argmin { f(π\') : π\' ∈ N(π(k)) \\ Tabú }',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'TABU',
  ),
  NotationEntry(
    symbol: 'π usuario',
    name: 'Secuencia del usuario',
    definition: 'Permutación de trabajos dada por el usuario; en talleres se '
        'usa como lista de prioridad. En Job Shop, Open Shop y Recurrente '
        'también puede darse una secuencia por máquina (π_i para cada Mi) y, '
        'en Open Shop, la ruta de cada trabajo.',
    formula: 'π = (j[1], j[2], …, j[n])',
    section: NotationSection.rules,
    contexts: {_p},
    ruleCode: 'SECUENCIA_USUARIO',
  ),
];

/// Entries shown by the Σ button of [context].
List<NotationEntry> notationFor(NotationContext context) =>
    [for (final e in kNotation) if (e.contexts.contains(context)) e];

/// The notation entry of rule [code], or null.
NotationEntry? notationForRule(String code) {
  var c = code.trim().toUpperCase();
  if (c == 'MINSLACK') c = 'MS';
  if (c.endsWith('_ADAPTADO')) c = c.substring(0, c.length - 9);
  if (c == 'LPT') c = 'SPT';
  if (c == 'MWR') c = 'LWR';
  for (final e in kNotation) {
    if (e.ruleCode == c) return e;
  }
  return null;
}

/// α field of the platform's environment [name] (as stored in the DB).
String alphaFor(String name) => switch (name.toUpperCase()) {
      'SINGLE MACHINE' => '1',
      'PARALLEL MACHINES' => 'Rm',
      'FLOW SHOP' => 'Fm',
      'FLEXIBLE FLOW SHOP' => 'FFc',
      'JOB SHOP' => 'Jm',
      'FLEXIBLE JOB SHOP' => 'FJc',
      'OPEN SHOP' => 'Om',
      'FLEXIBLE OPEN SHOP' => 'Om (flexible)',
      'RECURRENTE' => 'Jm',
      'FLEXIBLE RECURRENTE' => 'FJc',
      _ => name,
    };

/// β field: what every program in the platform may carry, plus the shop's
/// own (precedences, recirculation).
String betaFor(String name) {
  final n = name.toUpperCase();
  return [
    'rj',
    'sjk',
    'prmp',
    'brkdwn',
    if (n.contains('JOB') || n.contains('RECURRENTE') || n.contains('OPEN'))
      'prec',
    if (n.contains('RECURRENTE')) 'recrc',
  ].join(', ');
}

/// "α | β | γ" of environment [name]; γ is left open (each metric or
/// metaheuristic objective fills it).
String threeFieldFor(String name, {String gamma = 'γ'}) =>
    '${alphaFor(name)} | ${betaFor(name)} | $gamma';

/// [label] followed by its symbol while the global switch is on.
String withSymbol(String label, String symbol) =>
    showNotation.value ? '$label ($symbol)' : label;

// ── Widgets ────────────────────────────────────────────────────────────────

/// The Σ button: opens the notation of [notationContext].
class NotationButton extends StatelessWidget {
  final NotationContext notationContext;
  final String title;
  final Color? color;

  const NotationButton({
    super.key,
    required this.notationContext,
    required this.title,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TutorialTarget(
      id: 'sigma.${notationContext.name}',
      child: IconButton(
      tooltip: 'Notación teórica de esta pantalla',
      icon: Icon(Icons.functions,
          color: color ?? Theme.of(context).colorScheme.primary),
      onPressed: () => showNotationPanel(
        context,
        title: title,
        entries: notationFor(notationContext),
      ),
    ),
    );
  }
}

/// Dialog listing [entries].
Future<void> showNotationPanel(
  BuildContext context, {
  required String title,
  required List<NotationEntry> entries,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.functions),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in entries) NotationTile(entry: e),
            const SizedBox(height: 8),
            Text('Fuente: $notationReference',
                style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TutorialTarget(
          id: 'sigma.close',
          child: TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ),
      ],
    ),
  );
}

/// One entry: symbol, name, definition and formula.
class NotationTile extends StatelessWidget {
  final NotationEntry entry;
  const NotationTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              entry.symbol,
              style: theme.textTheme.titleSmall?.copyWith(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(entry.definition),
                if (entry.formula != null) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    entry.formula!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Strip with the key symbols of a screen, shown only while the global
/// switch is on.
class NotationStrip extends StatelessWidget {
  final NotationContext notationContext;
  const NotationStrip({super.key, required this.notationContext});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: showNotation,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final entries = notationFor(notationContext)
            .where((e) => e.section != NotationSection.rules)
            .toList();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.functions, size: 18),
              for (final e in entries)
                Tooltip(
                  message: '${e.name}. ${e.definition}'
                      '${e.formula == null ? '' : '\n${e.formula}'}',
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${e.symbol}: ${e.name}'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
