// lib/shared/dispatch_rule_info.dart
//
// A plain-language explanation of every dispatching rule the platform
// offers, shown wherever the user picks rules, so nobody has to remember
// what EDD or ATCS means. Descriptions follow docs/supuestos_y_logica_reglas.md.

/// What one rule does, in words a planner can use.
class DispatchRuleInfo {
  /// Name as stored in the database ("EDD", "SPT_ADAPTADO", ...).
  final String code;

  /// Full name.
  final String title;

  /// One line for lists.
  final String summary;

  /// How it decides, step by step.
  final String howItWorks;

  /// When it tends to give good results.
  final String goodFor;

  /// "Estática", "Dinámica", "Heurística" or "Metaheurística".
  final String kind;

  const DispatchRuleInfo({
    required this.code,
    required this.title,
    required this.summary,
    required this.howItWorks,
    required this.goodFor,
    required this.kind,
  });
}

const String _adaptedNote =
    'Es la versión dinámica: decide en cada momento en que una máquina queda '
    'libre, solo entre los trabajos que pueden empezar ya, y mide el tiempo '
    'REAL que tomaría cada uno (alistamiento desde el estado actual de la '
    'máquina + procesamiento + pausas por turno, mantenimiento o descanso).';

const Map<String, DispatchRuleInfo> _catalog = {
  'EDD': DispatchRuleInfo(
    code: 'EDD',
    title: 'Fecha de entrega más temprana (Earliest Due Date)',
    summary: 'Primero el trabajo que se debe entregar antes.',
    howItWorks:
        'Ordena los trabajos por su fecha de entrega, de la más cercana a la '
        'más lejana.',
    goodFor:
        'Reducir el retraso máximo y la tardanza máxima (es óptima para eso '
        'en una sola máquina).',
    kind: 'Estática',
  ),
  'SPT': DispatchRuleInfo(
    code: 'SPT',
    title: 'Tiempo de procesamiento más corto (Shortest Processing Time)',
    summary: 'Primero el trabajo más corto.',
    howItWorks:
        'Ordena por el tiempo de procesamiento, del menor al mayor. En Flow '
        'Shop se usa el tiempo en la primera estación; en los ambientes que '
        'despachan por operación, el tiempo de esa operación.',
    goodFor:
        'Reducir el tiempo promedio que los trabajos pasan en el sistema y el '
        'número de trabajos en espera.',
    kind: 'Estática',
  ),
  'LPT': DispatchRuleInfo(
    code: 'LPT',
    title: 'Tiempo de procesamiento más largo (Longest Processing Time)',
    summary: 'Primero el trabajo más largo.',
    howItWorks:
        'Ordena por el tiempo de procesamiento, del mayor al menor (mismo '
        'tiempo que usa SPT en cada ambiente).',
    goodFor:
        'Equilibrar la carga entre máquinas en paralelo y terminar todo antes '
        '(makespan).',
    kind: 'Estática',
  ),
  'FIFO': DispatchRuleInfo(
    code: 'FIFO',
    title: 'Primero en llegar, primero en salir (First In, First Out)',
    summary: 'Primero el trabajo que llegó (o estuvo disponible) antes.',
    howItWorks:
        'Ordena por la fecha de disponibilidad del trabajo. Cuando se decide '
        'por estación u operación, por la llegada a esa cola.',
    goodFor: 'Atender en orden justo; es la referencia contra la que se '
        'comparan las demás reglas.',
    kind: 'Estática',
  ),
  'WSPT': DispatchRuleInfo(
    code: 'WSPT',
    title: 'Tiempo de procesamiento ponderado más corto (Weighted SPT)',
    summary: 'Primero el que da más prioridad por minuto de trabajo.',
    howItWorks:
        'Calcula prioridad ÷ tiempo de procesamiento y atiende primero el '
        'valor más alto.',
    goodFor:
        'Reducir el tiempo de terminación ponderado cuando unos trabajos '
        'importan más que otros.',
    kind: 'Estática',
  ),
  'EDD_ADAPTADO': DispatchRuleInfo(
    code: 'EDD_ADAPTADO',
    title: 'EDD adaptado',
    summary: 'EDD decidido en cada momento, entre los que pueden empezar.',
    howItWorks: '$_adaptedNote El empate se resuelve por el menor tiempo real.',
    goodFor: 'Cumplir fechas cuando hay alistamientos o pausas importantes.',
    kind: 'Dinámica',
  ),
  'SPT_ADAPTADO': DispatchRuleInfo(
    code: 'SPT_ADAPTADO',
    title: 'SPT adaptado',
    summary: 'El que termina antes de verdad (con alistamiento y pausas).',
    howItWorks: '$_adaptedNote Elige el de menor tiempo real.',
    goodFor:
        'Igual que SPT, pero evita trabajos cortos con alistamientos largos.',
    kind: 'Dinámica',
  ),
  'LPT_ADAPTADO': DispatchRuleInfo(
    code: 'LPT_ADAPTADO',
    title: 'LPT adaptado',
    summary: 'El que ocupa más tiempo real la máquina.',
    howItWorks: '$_adaptedNote Elige el de mayor tiempo real.',
    goodFor: 'Equilibrar carga considerando alistamientos y pausas.',
    kind: 'Dinámica',
  ),
  'FIFO_ADAPTADO': DispatchRuleInfo(
    code: 'FIFO_ADAPTADO',
    title: 'FIFO adaptado',
    summary: 'FIFO decidido en cada momento, entre los que pueden empezar.',
    howItWorks: '$_adaptedNote Entre ellos atiende al que llegó antes.',
    goodFor: 'Orden de llegada sin dejar la máquina parada esperando.',
    kind: 'Dinámica',
  ),
  'WSPT_ADAPTADO': DispatchRuleInfo(
    code: 'WSPT_ADAPTADO',
    title: 'WSPT adaptado',
    summary: 'Más prioridad por minuto de tiempo real.',
    howItWorks: '$_adaptedNote Calcula prioridad ÷ tiempo real.',
    goodFor: 'Priorizar trabajos importantes considerando alistamientos.',
    kind: 'Dinámica',
  ),
  'MINSLACK': DispatchRuleInfo(
    code: 'MINSLACK',
    title: 'Holgura mínima (Minimum Slack)',
    summary: 'Primero el que tiene menos margen antes de su entrega.',
    howItWorks:
        'Holgura = fecha de entrega − cuándo terminaría si empieza ahora − '
        'trabajo que le falta. Atiende la menor; un trabajo ya atrasado tiene '
        'holgura negativa y va primero. Se recalcula en cada decisión.',
    goodFor: 'Reducir atrasos cuando las fechas de entrega son ajustadas.',
    kind: 'Dinámica',
  ),
  'CR': DispatchRuleInfo(
    code: 'CR',
    title: 'Razón crítica (Critical Ratio)',
    summary: 'Primero el que tiene menos tiempo disponible por trabajo pendiente.',
    howItWorks:
        'Razón = (fecha de entrega − ahora) ÷ trabajo que le falta. Menor que '
        '1 significa que ya no alcanza a cumplir. Atiende la razón más baja; '
        'se recalcula en cada decisión.',
    goodFor: 'Balancear urgencia y tamaño del trabajo.',
    kind: 'Dinámica',
  ),
  'ATCS': DispatchRuleInfo(
    code: 'ATCS',
    title: 'Costo de tardanza aparente con alistamientos (ATCS)',
    summary: 'Combina prioridad, tiempo, urgencia y costo de alistamiento.',
    howItWorks:
        'Índice de Lee, Bhaskaran y Pinedo (1997): favorece trabajos '
        'importantes y cortos, sube a medida que se acerca su entrega y '
        'castiga los que necesitan un alistamiento grande. Sus parámetros se '
        'ajustan solos a cada programa.',
    goodFor:
        'Reducir la tardanza ponderada cuando los alistamientos dependen de '
        'la secuencia.',
    kind: 'Dinámica',
  ),
  'LWR': DispatchRuleInfo(
    code: 'LWR',
    title: 'Menor trabajo restante (Least Work Remaining)',
    summary: 'Primero el trabajo al que le falta menos por hacer.',
    howItWorks:
        'Suma el tiempo de la operación actual y de las que le faltan al '
        'trabajo, y atiende la suma menor.',
    goodFor: 'Terminar pronto los trabajos casi listos y vaciar el taller.',
    kind: 'Dinámica',
  ),
  'MWR': DispatchRuleInfo(
    code: 'MWR',
    title: 'Mayor trabajo restante (Most Work Remaining)',
    summary: 'Primero el trabajo al que le falta más por hacer.',
    howItWorks:
        'Suma el tiempo de la operación actual y de las que le faltan al '
        'trabajo, y atiende la suma mayor.',
    goodFor:
        'Terminar todo antes (makespan); es la heurística clásica de Job Shop '
        'y Open Shop.',
    kind: 'Dinámica',
  ),
  'JOHNSON': DispatchRuleInfo(
    code: 'JOHNSON',
    title: 'Regla de Johnson',
    summary: 'Secuencia óptima para dos estaciones en línea.',
    howItWorks:
        'Pone primero, de menor a mayor, los trabajos más rápidos en la '
        'primera estación que en la segunda, y al final, de mayor a menor, '
        'los demás.',
    goodFor:
        'Minimizar el tiempo total en un Flow Shop de dos estaciones (es '
        'óptima ahí).',
    kind: 'Heurística',
  ),
  'CDS': DispatchRuleInfo(
    code: 'CDS',
    title: 'Campbell, Dudek y Smith (CDS)',
    summary: 'Extiende Johnson a más de dos estaciones.',
    howItWorks:
        'Agrupa las estaciones en dos máquinas ficticias de varias formas, '
        'aplica Johnson a cada una y se queda con la mejor.',
    goodFor: 'Flow Shop con varias estaciones, buscando terminar todo antes.',
    kind: 'Heurística',
  ),
  'GENETICS': DispatchRuleInfo(
    code: 'GENETICS',
    title: 'Algoritmo genético',
    summary: 'Busca una buena secuencia combinando y mutando soluciones.',
    howItWorks:
        'En una máquina, máquinas paralelas y Flow Shop es un algoritmo '
        'genético: genera secuencias, conserva las mejores y las combina. En '
        'los demás ambientes es un puntaje que combina urgencia (CR) y '
        'prioridad por minuto (WSPT).',
    goodFor:
        'Comparar contra las reglas simples; puede tardar más que ellas.',
    kind: 'Metaheurística',
  ),
  'TABU': DispatchRuleInfo(
    code: 'TABU',
    title: 'Búsqueda tabú',
    summary: 'Mejora una secuencia probando intercambios, sin repetir pasos.',
    howItWorks:
        'Parte de una secuencia y prueba intercambios de trabajos; recuerda '
        'los movimientos recientes para no volver atrás y conserva la mejor '
        'solución encontrada.',
    goodFor: 'Afinar la secuencia en una máquina o máquinas paralelas.',
    kind: 'Metaheurística',
  ),
};

/// The explanation of rule [code] (case-insensitive), or null if unknown.
/// "MS" is the same rule as "MINSLACK".
DispatchRuleInfo? dispatchRuleInfo(String code) {
  final c = code.trim().toUpperCase();
  return _catalog[c == 'MS' ? 'MINSLACK' : c];
}
