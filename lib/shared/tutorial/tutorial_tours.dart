// lib/shared/tutorial/tutorial_tours.dart
//
// The two guided tours of the in-app manual. They are EXAMPLES of two
// families, not "the tutorial of one environment": the app detects the
// environment from the program (see environment_detection.dart), so the same
// screens apply to every environment of the family.
//   * One machine per station (Single machine, Flow Shop, Job Shop, Open
//     Shop, Recurrente): illustrated with a Flow Shop.
//   * Several machines per station (Parallel machines and the flexible
//     variants): illustrated with a Flexible Job Shop.
// Each one builds a real production program from scratch in the tutorial
// workspace and, on the way, goes through everything the platform can do:
//   * Flow Shop: settings, stations, a route, a program with manual dates,
//     processing times, product families and setup matrix, duplicated jobs,
//     rules and the genetic algorithm, metrics, dashboard, Gantt, notation.
//   * Flexible Job Shop: stations with several machines, maintenance and
//     rests, two routes, automatic dates, times per machine, initial
//     machine states, composite rules, the user's own sequence, Gantt by
//     job, program management (duplicate, edit, delete) and the glossary.
import 'package:flutter/material.dart' show Icons;
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';

const _text = TutorialAdvance.text;
const _seen = TutorialAdvance.visible;
const _event = TutorialAdvance.event;
const _ok = TutorialAdvance.button;

/// Steps to enter one processing time: open the station's clock, type the
/// minutes and accept.
List<TutorialStep> _stationTime(String chapter, int job, int station,
    String stationName, String minutes,
    {bool severalMachines = false}) {
  final id = 'job$job.station$station';
  return [
    TutorialStep(
      chapter: chapter,
      title: 'Tiempo en $stationName',
      text: 'Pulsa el reloj de la estación $stationName para escribir su '
          'tiempo de proceso (pij).',
      target: '$id.time',
    ),
    if (severalMachines)
      TutorialStep(
        chapter: chapter,
        title: 'Una estación, varias máquinas',
        text: 'Esta estación tiene 2 máquinas. Aquí eliges cuál editar: cada '
            'una guarda su propio tiempo (una puede ser más rápida). El '
            'algoritmo decide en cuál procesar cada trabajo.',
        target: 'times.machine',
        advance: _ok,
      ),
    TutorialStep(
      chapter: chapter,
      title: 'Minutos de proceso',
      text: 'Escribe el tiempo en minutos y pulsa "Listo" aquí abajo.',
      target: 'times.processing',
      advance: _text,
      expectText: minutes,
    ),
    TutorialStep(
      chapter: chapter,
      title: 'Aceptar',
      text: 'Pulsa "Aceptar" para guardar el tiempo.',
      target: 'times.ok',
      advance: _event,
      event: 'stationTimesAccepted',
    ),
  ];
}

/// Steps to choose a product family (A-J) at one station.
List<TutorialStep> _family(
        String chapter, int job, int station, String stationName, String letter) =>
    [
      TutorialStep(
        chapter: chapter,
        title: 'Familia en $stationName: $letter',
        text: 'Abre la lista "Estado (familia)" de $stationName y elige '
            '"$letter". Los trabajos de distinta familia necesitan '
            'alistamiento (sjk) al cambiar de uno a otro en la máquina.',
        target: 'job$job.station$station.state',
        advance: _event,
        event: 'stateSelected',
        blockOutside: false,
      ),
    ];

// ═════════════════════════════════════════════════════════════════════════
// Tour 1: Flow Shop
// ═════════════════════════════════════════════════════════════════════════

const _c0 = '1 · Bienvenida y configuración';
const _c1 = '2 · Estaciones y máquinas';
const _c2 = '3 · Ruta de proceso';
const _c3 = '4 · Programa de producción';
const _c4 = '5 · Algoritmos';
const _c5 = '6 · Resultados';

final TutorialTour flowShopTour = TutorialTour(
  id: 'flow_shop',
  title: 'Ejemplo guiado: una máquina por estación (Flow Shop)',
  category: 'Una máquina por estación',
  environments: [
    'Máquina única',
    'Flow Shop',
    'Job Shop',
    'Open Shop',
    'Recurrente',
  ],
  icon: Icons.linear_scale,
  blurb: 'Panadería: 3 lotes de pan, todos por Mezcla → Horno → Empaque. '
      'Configuración, estaciones, una ruta, fechas, tiempos, familias y '
      'alistamiento, reglas, algoritmo genético, métricas, dashboard, '
      'Gantt y notación. Lo aprendido aplica igual a los demás ambientes '
      'con una máquina por estación: solo cambian las rutas del programa.',
  steps: [
    const TutorialStep(
      chapter: _c0,
      title: '¡Bienvenido al ejemplo!',
      text: 'Este ejemplo sirve para cualquier ambiente con UNA máquina por '
          'estación (el ambiente se detecta solo según tus rutas). Aquí '
          'programarás 3 lotes de pan que pasan todos por Mezcla → '
          'Horno → Empaque (un Flow Shop). Te diré exactamente qué hacer: '
          'lo iluminado es lo único que puedes tocar en cada paso. Trabajas '
          'en un espacio de prueba ("Tutorial"): tus datos reales no se '
          'tocan y vuelven al terminar.',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _c0,
      title: 'Configuración',
      text: 'Abre "Configuración": allí están el workspace, el horario de la '
          'planta y el formato de los tiempos.',
      target: 'menu.config',
    ),
    const TutorialStep(
      chapter: _c0,
      title: 'El horario de la planta',
      text: 'Elige "Horario": es el turno en que trabajan las máquinas. Lo '
          'que no cabe en el turno sigue al día siguiente.',
      target: 'config.nav.horario',
    ),
    const TutorialStep(
      chapter: _c0,
      title: 'Inicio y fin del turno',
      text: 'Pulsa una hora para cambiarla (se escribe HH:mm) y luego '
          '"Guardar". El horario es de cada workspace y viaja con él. Para '
          'el tutorial deja las que están.',
      target: 'horario.content',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _c0,
      title: 'Formato de tiempos',
      text: 'Elige "Formato de tiempos".',
      target: 'config.nav.formato',
    ),
    const TutorialStep(
      chapter: _c0,
      title: 'Minutos u hh:mm:ss',
      text: 'Aquí eliges si los tiempos se escriben en minutos (90) o en '
          'hh:mm:ss (01:30:00). Durante el tutorial usamos minutos.',
      target: 'formato.content',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _c0,
      title: 'Cerrar la configuración',
      text: 'En "Workspace" puedes crear otros workspaces y exportarlos o '
          'importarlos para seguir en otro equipo. Ahora cierra la '
          'configuración.',
      target: 'config.close',
    ),
    const TutorialStep(
      chapter: _c0,
      title: 'Notación teórica',
      text: 'Activa la notación teórica: verás los símbolos de la literatura '
          '(rj, dj, pij, Cmax…) junto a los nombres de la plataforma.',
      target: 'menu.notacion',
    ),
    // ── Stations ───────────────────────────────────────────────────────────
    const TutorialStep(
      chapter: _c1,
      title: 'Estaciones de trabajo',
      text: 'Una estación agrupa máquinas que hacen la misma operación. '
          'Abre "Estaciones de Trabajo".',
      target: 'menu/machines',
    ),
    const TutorialStep(
      chapter: _c1,
      title: 'Notación de esta pantalla',
      text: 'Con la notación activa ves esta franja: en la literatura cada '
          'máquina es Mi. El botón Σ abre la notación de cada pantalla.',
      target: 'sigma.machines',
      advance: _ok,
    ),
    for (final s in const [
      ('Mezcla', 'Amasado de la harina'),
      ('Horno', 'Horneado del pan'),
      ('Empaque', 'Empacado del producto'),
    ]) ...[
      TutorialStep(
        chapter: _c1,
        title: 'Nueva estación: ${s.$1}',
        text: 'Pulsa "Agregar estacion de trabajo".',
        target: 'machines.addStation',
      ),
      TutorialStep(
        chapter: _c1,
        title: 'Nombre de la estación',
        text: 'Escribe el nombre y pulsa "Listo".',
        target: 'station.name',
        advance: _text,
        expectText: s.$1,
      ),
      TutorialStep(
        chapter: _c1,
        title: 'Descripción (opcional)',
        text: 'Escribe una descripción corta, por ejemplo "${s.$2}", y pulsa '
            '"Listo".',
        target: 'station.desc',
        advance: _text,
      ),
      TutorialStep(
        chapter: _c1,
        title: 'Agregar',
        text: 'Pulsa "Agregar". La estación aparecerá en la lista.',
        target: 'station.add',
        advance: _seen,
        waitFor: 'station:${s.$1}',
      ),
    ],
    for (final m in const [
      ('Mezcla', 'Mezcladora'),
      ('Horno', 'Horno A'),
      ('Empaque', 'Empacadora'),
    ]) ...[
      TutorialStep(
        chapter: _c1,
        title: 'Máquina para ${m.$1}',
        text: 'Cada estación necesita al menos una máquina. Pulsa + en la fila '
            'de ${m.$1}.',
        target: 'station.addMachine:${m.$1}',
      ),
      TutorialStep(
        chapter: _c1,
        title: 'Nombre de la máquina',
        text: 'Escribe el nombre y pulsa "Listo".',
        target: 'machine.name',
        advance: _text,
        expectText: m.$2,
      ),
      const TutorialStep(
        chapter: _c1,
        title: 'Disponible desde ahora',
        text: 'Elige "Ahora": la máquina está disponible desde hoy. Con '
            '"Fecha específica" indicarías desde cuándo (dd/mm/aaaa hh:mm).',
        target: 'machine.startMode',
      ),
      if (m.$1 == 'Mezcla')
        const TutorialStep(
          chapter: _c1,
          title: 'Descansos automáticos',
          text: 'Aquí defines cuánto puede trabajar seguido la máquina y '
              'cuánto descansa. "No aplica" deja la máquina sin descansos, '
              'que es lo que usamos ahora.',
          target: 'machine.rest',
          advance: _ok,
        ),
      if (m.$1 == 'Mezcla')
        const TutorialStep(
          chapter: _c1,
          title: 'Mantenimientos',
          text: 'También puedes programar mantenimientos semanales (días, '
              'hora de inicio y duración). Lo verás en acción en el ejemplo '
              'de varias máquinas por estación.',
          target: 'machine.maintenance',
          advance: _ok,
        ),
      const TutorialStep(
        chapter: _c1,
        title: 'Agregar la máquina',
        text: 'Pulsa "Agregar" (abajo del formulario).',
        target: 'machine.add',
        advance: _event,
        event: 'machineAdded',
      ),
    ],
    // ── Route ──────────────────────────────────────────────────────────────
    const TutorialStep(
      chapter: _c2,
      title: 'Rutas de proceso',
      text: 'La ruta es el orden de estaciones que recorre el producto. Abre '
          '"Rutas de Proceso".',
      target: 'menu/sequences',
    ),
    const TutorialStep(
      chapter: _c2,
      title: 'Nueva ruta',
      text: 'Pulsa "Nueva ruta de proceso".',
      target: 'routes.new',
    ),
    for (final s in const ['Mezcla', 'Horno', 'Empaque'])
      TutorialStep(
        chapter: _c2,
        title: 'Agregar $s a la ruta',
        text: 'Haz clic en "$s" en la lista de estaciones.',
        target: 'routes.station:$s',
        advance: _event,
        event: 'stationAddedToRoute',
      ),
    const TutorialStep(
      chapter: _c2,
      title: 'Modo Conectar',
      text: 'Ahora une las estaciones con flechas (precedencias). Pulsa '
          '"Conectar" en la barra.',
      target: 'routes.tools',
    ),
    const TutorialStep(
      chapter: _c2,
      title: 'Mezcla → Horno',
      text: 'En el tablero haz clic en Mezcla y luego en Horno.',
      target: 'routes.canvas',
      advance: _event,
      event: 'edgeAdded',
    ),
    const TutorialStep(
      chapter: _c2,
      title: 'Horno → Empaque',
      text: 'Ahora haz clic en Horno y luego en Empaque.',
      target: 'routes.canvas',
      advance: _event,
      event: 'edgeAdded',
    ),
    const TutorialStep(
      chapter: _c2,
      title: 'Herramientas del tablero',
      text: '"Seleccionar" mueve estaciones o elimina flechas, "Ordenar" '
          'acomoda el grafo y la lupa acerca o aleja. El editor no permite '
          'ciclos.',
      target: 'routes.tools',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _c2,
      title: 'Nombre de la ruta',
      text: 'Escribe el nombre y pulsa "Listo".',
      target: 'routes.name',
      advance: _text,
      expectText: 'Pan blanco',
    ),
    const TutorialStep(
      chapter: _c2,
      title: 'Guardar la ruta',
      text: 'Pulsa "Guardar ruta".',
      target: 'routes.save',
      advance: _seen,
      waitFor: 'route:Pan blanco',
    ),
    // ── Program ────────────────────────────────────────────────────────────
    const TutorialStep(
      chapter: _c3,
      title: 'Programas de producción',
      text: 'Un programa reúne los trabajos (jobs) que hay que producir. '
          'Abre "Programas de produccion".',
      target: 'menu/orders',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Nuevo programa',
      text: 'Pulsa "Nuevo Programa de Producción".',
      target: 'orders.new',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Fechas manuales o automáticas',
      text: 'En "Manual" escribes la fecha de disponibilidad (rj) y de '
          'entrega (dj) de cada trabajo; en "Automático" se calculan al '
          'guardar. Aquí usaremos Manual (ya está elegido).',
      target: 'order.dateMode',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Primer trabajo',
      text: 'Pulsa "Agregar Job".',
      target: 'order.addJob',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Nombre del trabajo',
      text: 'Borra el número y escribe el nombre del lote; luego "Listo".',
      target: 'job1.id',
      advance: _text,
      expectText: 'Lote 1',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Prioridad (wj)',
      text: 'Escribe la prioridad: más alta = más importante.',
      target: 'job1.priority',
      advance: _text,
      expectText: '2',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Fecha de disponibilidad (rj)',
      text: 'Pulsa el calendario de "fecha de disponibilidad".',
      target: 'job1.availableDate',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Elige hoy',
      text: 'Elige el día de hoy y pulsa "Aceptar" en el calendario.',
      advance: _event,
      event: 'datePicked',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Hora de disponibilidad',
      text: 'Pulsa el botón "Hora" de la misma fila.',
      target: 'job1.availableHour',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Escribe la hora',
      text: 'Escribe 08:00 (hora 08, minuto 00) y pulsa "Aceptar".',
      advance: _event,
      event: 'timePicked',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Fecha de entrega (dj)',
      text: 'Ahora el calendario de "fecha de entrega".',
      target: 'job1.dueDate',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Entrega: hoy',
      text: 'Elige hoy y pulsa "Aceptar".',
      advance: _event,
      event: 'datePicked',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Hora de entrega',
      text: 'Pulsa el botón "Hora" de la fila de entrega.',
      target: 'job1.dueHour',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Entrega a las 12:00',
      text: 'Escribe 12:00 y pulsa "Aceptar".',
      advance: _event,
      event: 'timePicked',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Ruta del trabajo',
      text: 'Abre la lista "Seleccionar ruta de proceso" y elige "Pan '
          'blanco". Aparecerán sus 3 estaciones.',
      target: 'job1.route',
      advance: _event,
      event: 'routeSelected',
      blockOutside: false,
    ),
    ..._stationTime(_c3, 1, 0, 'Mezcla', '30'),
    ..._family(_c3, 1, 0, 'Mezcla', 'A'),
    ..._stationTime(_c3, 1, 1, 'Horno', '60'),
    ..._family(_c3, 1, 1, 'Horno', 'A'),
    ..._stationTime(_c3, 1, 2, 'Empaque', '15'),
    ..._family(_c3, 1, 2, 'Empaque', 'A'),
    const TutorialStep(
      chapter: _c3,
      title: 'Duplicar el trabajo',
      text: 'Para no repetir todo, duplica el Lote 1: se copian ruta, fechas, '
          'tiempos y familias. Pulsa el botón de copiar del trabajo.',
      target: 'job1.duplicate',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Lote 2',
      text: 'En el trabajo nuevo, borra el número y escribe el nombre.',
      target: 'job2.id',
      advance: _text,
      expectText: 'Lote 2',
    ),
    ..._stationTime(_c3, 2, 1, 'Horno (Lote 2)', '45'),
    ..._family(_c3, 2, 1, 'Horno (Lote 2)', 'B'),
    const TutorialStep(
      chapter: _c3,
      title: 'Otro duplicado',
      text: 'Duplica el Lote 2 para crear el tercero.',
      target: 'job2.duplicate',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Lote 3',
      text: 'Escribe el nombre del tercer lote.',
      target: 'job3.id',
      advance: _text,
      expectText: 'Lote 3',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Prioridad del Lote 3',
      text: 'Ponle prioridad 5: es el más urgente para el cliente.',
      target: 'job3.priority',
      advance: _text,
      expectText: '5',
    ),
    ..._stationTime(_c3, 3, 0, 'Mezcla (Lote 3)', '20'),
    const TutorialStep(
      chapter: _c3,
      title: 'Matriz de alistamiento',
      text: 'Pasar de la familia A a la B en el horno requiere preparar la '
          'máquina. Pulsa "Definir matriz de tiempos de alistamiento".',
      target: 'order.matrix',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Tiempos A → B',
      text: 'Elige la máquina "Horno A". En la fila A, columna B escribe 15 '
          '(minutos para pasar de A a B) y en la fila B, columna A escribe '
          '10. Luego pulsa "Guardar".',
      target: 'matrix.save',
      advance: _event,
      event: 'matrixSaved',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Cerrar la matriz',
      text: 'Pulsa "Cerrar".',
      target: 'matrix.close',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Crear el programa',
      text: 'Pulsa "Crear programa de produccion". Si falta algo, la app te '
          'dirá qué completar.',
      target: 'order.save',
      advance: _event,
      event: 'orderSaved',
    ),
    const TutorialStep(
      chapter: _c3,
      title: '¡Programa guardado!',
      text: 'Pulsa "OK" para volver a la lista.',
      target: 'order.savedOk',
    ),
    const TutorialStep(
      chapter: _c3,
      title: 'Tu programa',
      text: 'Aquí está tu programa con sus trabajos y rutas. La plataforma '
          'detectó sola el ambiente: FLOW SHOP (todos siguen la misma ruta y '
          'cada estación tiene una sola máquina). Si las rutas fueran '
          'distintas sería JOB SHOP, y si no tuvieran orden, OPEN SHOP: '
          'tú no eliges el ambiente, lo deduce la plataforma.',
      target: 'order.card.latest',
      advance: _ok,
    ),
    // ── Algorithms ─────────────────────────────────────────────────────────
    const TutorialStep(
      chapter: _c4,
      title: 'Programar',
      text: 'Pulsa "programar" para elegir con qué algoritmos ordenarlo.',
      target: 'order.programar.latest',
    ),
    const TutorialStep(
      chapter: _c4,
      title: 'Contenido del programa',
      text: 'Aquí puedes revisar los trabajos y abrir la ruta antes de '
          'calcular.',
      target: 'picker.summary',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _c4,
      title: 'Guía de reglas',
      text: 'Este botón explica todas las reglas del ambiente; el ícono ? de '
          'cada regla explica solo esa.',
      target: 'picker.guide',
      advance: _ok,
    ),
    for (final r in const [
      ('EDD', 'Primero la entrega más próxima (min dj).'),
      ('SPT', 'Primero el más corto (min pj).'),
      ('WSPT', 'Más prioridad por minuto (max wj/pj).'),
      ('GENETICS', 'Algoritmo genético: evoluciona secuencias.'),
    ])
      TutorialStep(
        chapter: _c4,
        title: 'Marca ${r.$1}',
        text: '${r.$2} Marca la casilla.',
        target: 'picker.rule:${r.$1}',
      ),
    const TutorialStep(
      chapter: _c4,
      title: 'Configurar el genético',
      text: 'Pulsa el ícono de ajustes de GENETICS.',
      target: 'picker.tune:GENETICS',
    ),
    const TutorialStep(
      chapter: _c4,
      title: 'Función objetivo',
      text: 'Abre la lista y elige "Tardanza total · Σ Tj": el genético '
          'buscará la secuencia con menos retraso. Luego pulsa "Entendido".',
      target: 'ga.objective',
      advance: _ok,
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _c4,
      title: 'Parámetros',
      text: 'También puedes cambiar población, generaciones, cruce, '
          'elitismo y semilla. Sube la mutación: escribe 0.2.',
      target: 'ga.mutation',
      advance: _text,
      expectText: '0.2',
    ),
    const TutorialStep(
      chapter: _c4,
      title: 'Guardar configuración',
      text: 'Pulsa "Guardar Configuracion".',
      target: 'ga.save',
      advance: _event,
      event: 'geneticConfigured',
    ),
    const TutorialStep(
      chapter: _c4,
      title: 'Calcular',
      text: 'Pulsa "Calcular". El genético puede tardar unos segundos.',
      target: 'picker.calc',
    ),
    // ── Results ────────────────────────────────────────────────────────────
    const TutorialStep(
      chapter: _c5,
      title: 'Tabla de métricas',
      text: 'Cada fila es un algoritmo y cada columna un indicador (makespan, '
          'flujo, tardanza, anticipo…). Verde es el mejor valor y rojo el '
          'peor. Pasa el mouse por un encabezado para ver su definición.',
      target: 'metrics.tabs',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Diagrama de Gantt',
      text: 'Pulsa el ícono de barras de la fila EDD.',
      target: 'metrics.gantt:EDD',
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Leer el Gantt',
      text: 'Cada barra es una operación en su máquina, a lo largo del '
          'tiempo. Las partes de alistamiento e interrupciones se ven '
          'diferenciadas.',
      target: 'gantt.chart',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Controles del Gantt',
      text: 'Aquí cambias de algoritmo sin volver atrás y alternas la vista '
          '"Por Máquina" o "Por Job". Debajo, el zoom horizontal y vertical.',
      target: 'gantt.controls',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Volver',
      text: 'Pulsa la flecha ← de arriba a la izquierda para volver a las '
          'métricas.',
      advance: _seen,
      waitFor: 'metrics.tabs',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Detalle de tareas',
      text: 'El ícono de tabla de cada fila muestra inicio y fin de cada '
          'operación. Pulsa el de GENETICS.',
      target: 'metrics.detail:GENETICS',
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Volver otra vez',
      text: 'Revisa la tabla y vuelve con la flecha ←.',
      advance: _seen,
      waitFor: 'metrics.tabs',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Dashboard',
      text: 'Pulsa la pestaña "Dashboard".',
      target: 'metrics.tabs',
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Ranking y recomendado',
      text: 'Marca o desmarca los indicadores que te importan (por ejemplo '
          'Anticipo total): las filas se ordenan por puesto promedio y la '
          'primera es la "Recomendada".',
      target: 'dashboard.scoreChips',
      advance: _ok,
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Notación de las métricas',
      text: 'Pulsa Σ para ver cada indicador en notación: Cmax, Σ(Cj − rj), '
          'ΣTj, ΣEj…',
      target: 'sigma.metrics',
    ),
    const TutorialStep(
      chapter: _c5,
      title: 'Cerrar',
      text: 'Pulsa "Cerrar".',
      target: 'sigma.close',
    ),
    const TutorialStep(
      chapter: _c5,
      title: '¡Terminaste el ejemplo de una máquina por estación!',
      text: 'Creaste estaciones, una ruta y un programa, lo programaste con '
          'reglas y un genético y comparaste los resultados. Los mismos '
          'pasos sirven para Máquina única, Job Shop, Open Shop y '
          'Recurrente. Al terminar vuelves a tu workspace. Si quieres ver '
          'varias máquinas por estación, mantenimientos, tu propia '
          'secuencia y la gestión de programas, haz el ejemplo de varias '
          'máquinas por estación.',
      advance: _ok,
    ),
  ],
);

// ═════════════════════════════════════════════════════════════════════════
// Tour 2: Flexible Job Shop
// ═════════════════════════════════════════════════════════════════════════

const _d0 = '1 · Taller con varias máquinas';
const _d1 = '2 · Dos rutas distintas';
const _d2 = '3 · Programa con fechas automáticas';
const _d3 = '4 · Reglas y secuencia propia';
const _d4 = '5 · Resultados';
const _d5 = '6 · Gestión de programas';

final TutorialTour flexibleJobShopTour = TutorialTour(
  id: 'flexible_job_shop',
  title: 'Ejemplo guiado: varias máquinas por estación (Flexible Job Shop)',
  category: 'Varias máquinas por estación',
  environments: [
    'Máquinas paralelas',
    'Flexible Flow Shop',
    'Flexible Job Shop',
    'Flexible Open Shop',
    'Flexible Recurrente',
  ],
  icon: Icons.hub_outlined,
  blurb: 'Taller: ejes y bridas con rutas distintas y estaciones con 2 '
      'máquinas. Descansos y mantenimientos, fechas automáticas, '
      'tiempos por máquina, estado inicial, reglas compuestas, tu propia '
      'secuencia, Gantt por trabajo y gestión de programas. Aplica igual '
      'a los demás ambientes con varias máquinas por estación.',
  steps: [
    const TutorialStep(
      chapter: _d0,
      title: '¡Bienvenido al ejemplo!',
      text: 'Este ejemplo sirve para cualquier ambiente con VARIAS máquinas '
          'en alguna estación (máquinas paralelas y las variantes '
          'flexibles). Un taller fabrica ejes y bridas: cada pieza tiene su '
          'propia ruta y algunas estaciones tienen 2 máquinas, así que es '
          'un Flexible Job Shop. Trabajas en el espacio "Tutorial"; tus '
          'datos no se tocan.',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _d0,
      title: 'Estaciones',
      text: 'Abre "Estaciones de Trabajo".',
      target: 'menu/machines',
    ),
    for (final s in const ['Sierra', 'Torno', 'Pintura']) ...[
      TutorialStep(
        chapter: _d0,
        title: 'Estación $s',
        text: 'Pulsa "Agregar estacion de trabajo".',
        target: 'machines.addStation',
      ),
      TutorialStep(
        chapter: _d0,
        title: 'Nombre',
        text: 'Escribe el nombre y pulsa "Listo".',
        target: 'station.name',
        advance: _text,
        expectText: s,
      ),
      TutorialStep(
        chapter: _d0,
        title: 'Agregar',
        text: 'Pulsa "Agregar".',
        target: 'station.add',
        advance: _seen,
        waitFor: 'station:$s',
      ),
    ],
    for (final m in const [('Sierra', '2'), ('Torno', '2'), ('Pintura', '1')]) ...[
      TutorialStep(
        chapter: _d0,
        title: 'Máquinas de ${m.$1}',
        text: 'Pulsa + en la fila de ${m.$1}.',
        target: 'station.addMachine:${m.$1}',
      ),
      TutorialStep(
        chapter: _d0,
        title: 'Nombre base',
        text: 'Escribe el nombre. Si creas varias, se numeran solas '
            '(${m.$1}, ${m.$1} 2…).',
        target: 'machine.name',
        advance: _text,
        expectText: m.$1,
      ),
      const TutorialStep(
        chapter: _d0,
        title: 'Disponible ahora',
        text: 'Elige "Ahora".',
        target: 'machine.startMode',
      ),
      if (m.$1 == 'Torno')
        const TutorialStep(
          chapter: _d0,
          title: 'Descanso tras uso continuo',
          text: 'Desmarca "No aplica descanso automático" y escribe 240 en '
              'procesamiento continuo y 15 en descanso: tras 4 horas seguidas '
              'el torno para 15 minutos. Luego pulsa "Entendido".',
          target: 'machine.rest',
          advance: _ok,
          blockOutside: false,
        ),
      if (m.$1 == 'Pintura')
        const TutorialStep(
          chapter: _d0,
          title: 'Mantenimiento semanal',
          text: 'Escribe "Limpieza", marca el viernes, pon hora de inicio '
              '14:00 y duración 60, y pulsa "Agregar Mantenimiento". La '
              'cabina no trabajará en ese horario (brkdwn). Luego "Entendido".',
          target: 'machine.maintenance',
          advance: _ok,
          blockOutside: false,
        ),
      TutorialStep(
        chapter: _d0,
        title: 'Cantidad: ${m.$2}',
        text: 'Escribe cuántas máquinas iguales crear y pulsa "Listo".',
        target: 'machine.quantity',
        advance: _text,
        expectText: m.$2,
      ),
      const TutorialStep(
        chapter: _d0,
        title: 'Agregar',
        text: 'Pulsa "Agregar".',
        target: 'machine.add',
        advance: _event,
        event: 'machineAdded',
      ),
    ],
    const TutorialStep(
      chapter: _d0,
      title: 'Ver las máquinas',
      text: 'Abre la fila de Sierra para ver sus 2 máquinas. Desde cada una '
          'puedes editarla, borrarla o configurar sus inactividades.',
      target: 'station:Sierra',
      advance: _ok,
      blockOutside: false,
    ),
    // ── Routes ─────────────────────────────────────────────────────────────
    const TutorialStep(
      chapter: _d1,
      title: 'Rutas',
      text: 'Abre "Rutas de Proceso".',
      target: 'menu/sequences',
    ),
    for (final r in const [
      ('Eje', ['Sierra', 'Torno', 'Pintura']),
      ('Brida', ['Torno', 'Sierra', 'Pintura']),
    ]) ...[
      TutorialStep(
        chapter: _d1,
        title: 'Ruta "${r.$1}"',
        text: 'Pulsa "Nueva ruta de proceso".',
        target: 'routes.new',
      ),
      for (final s in r.$2)
        TutorialStep(
          chapter: _d1,
          title: 'Agregar $s',
          text: 'Haz clic en "$s".',
          target: 'routes.station:$s',
          advance: _event,
          event: 'stationAddedToRoute',
        ),
      const TutorialStep(
        chapter: _d1,
        title: 'Conectar',
        text: 'Pulsa "Conectar".',
        target: 'routes.tools',
      ),
      TutorialStep(
        chapter: _d1,
        title: '${r.$2[0]} → ${r.$2[1]}',
        text: 'Clic en ${r.$2[0]} y luego en ${r.$2[1]}.',
        target: 'routes.canvas',
        advance: _event,
        event: 'edgeAdded',
      ),
      TutorialStep(
        chapter: _d1,
        title: '${r.$2[1]} → ${r.$2[2]}',
        text: 'Clic en ${r.$2[1]} y luego en ${r.$2[2]}.',
        target: 'routes.canvas',
        advance: _event,
        event: 'edgeAdded',
      ),
      TutorialStep(
        chapter: _d1,
        title: 'Nombre',
        text: 'Escribe el nombre de la ruta.',
        target: 'routes.name',
        advance: _text,
        expectText: r.$1,
      ),
      TutorialStep(
        chapter: _d1,
        title: 'Guardar',
        text: 'Pulsa "Guardar ruta".',
        target: 'routes.save',
        advance: _seen,
        waitFor: 'route:${r.$1}',
      ),
    ],
    const TutorialStep(
      chapter: _d1,
      title: 'Abrir una ruta guardada',
      text: 'Haz clic en "Eje" en la lista.',
      target: 'route:Eje',
    ),
    const TutorialStep(
      chapter: _d1,
      title: 'Editar o duplicar',
      text: '"Editar" la modifica y "Duplicar" crea una copia para hacer una '
          'variante sin empezar de cero. Las rutas en uso no se pueden '
          'borrar.',
      target: 'routes.viewActions',
      advance: _ok,
    ),
    // ── Program ────────────────────────────────────────────────────────────
    const TutorialStep(
      chapter: _d2,
      title: 'Programas',
      text: 'Abre "Programas de produccion".',
      target: 'menu/orders',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Nuevo programa',
      text: 'Pulsa "Nuevo Programa de Producción".',
      target: 'orders.new',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Fechas automáticas',
      text: 'Elige "Automático": solo indicas horas y las fechas se calculan '
          'al guardar.',
      target: 'order.dateMode',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Primer trabajo',
      text: 'Pulsa "Agregar Job".',
      target: 'order.addJob',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Nombre',
      text: 'Borra el número y escribe el nombre.',
      target: 'job1.id',
      advance: _text,
      expectText: 'Eje A',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Prioridad',
      text: 'Escribe la prioridad.',
      target: 'job1.priority',
      advance: _text,
      expectText: '2',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Hora de inicio',
      text: 'Pulsa "Hora actual" junto a "Hora de inicio".',
      target: 'job1.autoStart',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Escribe 07:00',
      text: 'Escribe 07:00 y pulsa "Aceptar".',
      advance: _event,
      event: 'timePicked',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Ruta "Eje"',
      text: 'Abre "Seleccionar ruta de proceso" y elige "Eje".',
      target: 'job1.route',
      advance: _event,
      event: 'routeSelected',
      blockOutside: false,
    ),
    ..._stationTime(_d2, 1, 0, 'Sierra', '30', severalMachines: true),
    ..._stationTime(_d2, 1, 1, 'Torno', '50', severalMachines: true),
    ..._stationTime(_d2, 1, 2, 'Pintura', '20'),
    ..._family(_d2, 1, 1, 'Torno', 'A'),
    const TutorialStep(
      chapter: _d2,
      title: 'Duplicar',
      text: 'Duplica "Eje A" para crear otro eje.',
      target: 'job1.duplicate',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Eje B',
      text: 'Escribe el nombre del segundo eje.',
      target: 'job2.id',
      advance: _text,
      expectText: 'Eje B',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Una brida',
      text: 'Las bridas usan otra ruta. Pulsa "Agregar Job".',
      target: 'order.addJob',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Nombre',
      text: 'Escribe el nombre.',
      target: 'job3.id',
      advance: _text,
      expectText: 'Brida A',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Prioridad',
      text: 'Escribe la prioridad.',
      target: 'job3.priority',
      advance: _text,
      expectText: '3',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Ruta "Brida"',
      text: 'Elige la ruta "Brida": Torno → Sierra → Pintura.',
      target: 'job3.route',
      advance: _event,
      event: 'routeSelected',
      blockOutside: false,
    ),
    ..._stationTime(_d2, 3, 0, 'Torno', '40', severalMachines: true),
    ..._stationTime(_d2, 3, 1, 'Sierra', '25', severalMachines: true),
    ..._stationTime(_d2, 3, 2, 'Pintura', '20'),
    ..._family(_d2, 3, 0, 'Torno', 'B'),
    const TutorialStep(
      chapter: _d2,
      title: 'Estado inicial de las máquinas',
      text: 'Pulsa "Definir estado inicial de máquinas": la familia que tiene '
          'cada máquina antes del primer trabajo.',
      target: 'order.initialStates',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Torno en A',
      text: 'Pon "A" en las dos máquinas Torno y pulsa "Guardar". Así el '
          'primer eje (familia A) no paga alistamiento.',
      target: 'initial.save',
      advance: _event,
      event: 'initialStatesSaved',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Alistamiento en el torno',
      text: 'Pulsa "Definir matriz de tiempos de alistamiento".',
      target: 'order.matrix',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'A ↔ B en el torno',
      text: 'Elige la máquina "Torno", escribe 20 en A → B y 20 en B → A y '
          'pulsa "Guardar". Con "Copiar matriz de otra máquina" la pasas al '
          'otro torno.',
      target: 'matrix.save',
      advance: _event,
      event: 'matrixSaved',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Cerrar',
      text: 'Pulsa "Cerrar".',
      target: 'matrix.close',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Crear el programa',
      text: 'Pulsa "Crear programa de produccion".',
      target: 'order.save',
      advance: _event,
      event: 'orderSaved',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'OK',
      text: 'Pulsa "OK".',
      target: 'order.savedOk',
    ),
    const TutorialStep(
      chapter: _d2,
      title: 'Ambiente detectado',
      text: 'Rutas distintas y estaciones con varias máquinas: la plataforma '
          'lo clasificó como FLEXIBLE JOB SHOP (FJc en la notación). La '
          'regla es general: una estación con más de una máquina da la '
          'variante flexible de cada ambiente.',
      target: 'order.card.latest',
      advance: _ok,
    ),
    // ── Rules and own sequence ─────────────────────────────────────────────
    const TutorialStep(
      chapter: _d3,
      title: 'Programar',
      text: 'Pulsa "programar".',
      target: 'order.programar.latest',
    ),
    for (final r in const [
      ('MS', 'Holgura mínima: primero el de menos margen.'),
      ('ATCS', 'Índice de tardanza aparente con alistamientos.'),
      ('PRIORIDAD_COMPUESTA', 'Combina urgencia (1/CR) y prioridad (w/p).'),
    ])
      TutorialStep(
        chapter: _d3,
        title: 'Marca ${r.$1}',
        text: '${r.$2} Marca la casilla.',
        target: 'picker.rule:${r.$1}',
      ),
    const TutorialStep(
      chapter: _d3,
      title: 'Tu propia secuencia',
      text: 'Además de las reglas puedes probar el orden que tú propones. '
          'Pulsa "Definir".',
      target: 'picker.userSeq',
    ),
    const TutorialStep(
      chapter: _d3,
      title: 'Ordena los trabajos',
      text: 'Arrastra con ≡ la "Brida A" al primer lugar (o usa "Partir de" '
          'EDD, FIFO o Prioridad). En un taller este orden es la prioridad '
          'al despachar. Luego pulsa "Entendido".',
      target: 'useq.list',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _d3,
      title: 'Usar la secuencia',
      text: 'Pulsa "Usar esta secuencia".',
      target: 'useq.ok',
      advance: _event,
      event: 'userSequenceDefined',
    ),
    const TutorialStep(
      chapter: _d3,
      title: 'Calcular',
      text: 'Pulsa "Calcular".',
      target: 'picker.calc',
    ),
    // ── Results ────────────────────────────────────────────────────────────
    const TutorialStep(
      chapter: _d4,
      title: 'Comparación',
      text: 'Tu secuencia aparece como SECUENCIA_USUARIO junto a las reglas, '
          'con los mismos indicadores.',
      target: 'metrics.tabs',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _d4,
      title: 'Gantt de tu secuencia',
      text: 'Pulsa el ícono de barras de la fila SECUENCIA_USUARIO.',
      target: 'metrics.gantt:SECUENCIA_USUARIO',
    ),
    const TutorialStep(
      chapter: _d4,
      title: 'Vista por trabajo',
      text: 'Cambia a "Por Job": ves la ruta de cada pieza y en qué máquina '
          'quedó cada operación. Luego "Entendido".',
      target: 'gantt.controls',
      advance: _ok,
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _d4,
      title: 'Volver',
      text: 'Vuelve con la flecha ←.',
      advance: _seen,
      waitFor: 'metrics.tabs',
      blockOutside: false,
    ),
    const TutorialStep(
      chapter: _d4,
      title: 'Dashboard',
      text: 'Abre la pestaña "Dashboard" y mira quién quedó "Recomendado".',
      target: 'metrics.tabs',
    ),
    const TutorialStep(
      chapter: _d4,
      title: 'Volver a los programas',
      text: 'Vuelve con la flecha ← a la lista de programas.',
      advance: _seen,
      waitFor: 'order.card.latest',
      blockOutside: false,
    ),
    // ── Management ─────────────────────────────────────────────────────────
    const TutorialStep(
      chapter: _d5,
      title: 'Buscar y filtrar',
      text: 'Con muchos programas, busca por trabajo, ruta o número y filtra '
          'por ambiente o ruta.',
      target: 'orders.filters',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _d5,
      title: 'Duplicar el programa',
      text: 'Pulsa el ícono de copiar: se copian trabajos, tiempos y la '
          'matriz de alistamiento.',
      target: 'order.copy.latest',
      advance: _event,
      event: 'orderDuplicated',
    ),
    const TutorialStep(
      chapter: _d5,
      title: 'Editar',
      text: 'El lápiz abre el programa para cambiar trabajos, fechas o '
          'tiempos.',
      target: 'order.edit.latest',
      advance: _ok,
    ),
    const TutorialStep(
      chapter: _d5,
      title: 'Eliminar la copia',
      text: 'La copia es el programa más reciente. Pulsa la papelera para '
          'eliminarla.',
      target: 'order.delete.latest',
      advance: _event,
      event: 'orderDeleted',
    ),
    const TutorialStep(
      chapter: _d5,
      title: 'Glosario de notación',
      text: 'Por último, abre "Glosario de notación": todos los símbolos y '
          'fórmulas de las reglas, con buscador.',
      target: 'menu/notacion',
    ),
    const TutorialStep(
      chapter: _d5,
      title: '¡Completaste el ejemplo!',
      text: 'Ya conoces toda la plataforma: estaciones, máquinas, '
          'mantenimientos, rutas, programas, alistamientos, reglas, '
          'metaheurísticas, tu propia secuencia, métricas, Gantt, gestión y '
          'notación. Al terminar vuelves a tu workspace.',
      advance: _ok,
    ),
  ],
);

final List<TutorialTour> kTours = [flowShopTour, flexibleJobShopTour];
