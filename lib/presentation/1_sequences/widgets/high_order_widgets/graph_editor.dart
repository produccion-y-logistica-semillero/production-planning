// widgets/high_order_widgets/graph_editor.dart
//
// Editor de grafo para rutas de proceso (Flutter desktop).
// - Nodos rectangulares (máquinas) y aristas dirigidas (source -> target).
// - Tap-to-connect: tap nodo A -> aparece flecha fantasma -> tap nodo B para crear A->B.
// - Selección de nodo/arista y borrado con Esc.
// - Reasignación de extremos de la arista mediante "handles" (círculos azules).
// - Validación DAG: no permite autolazos ni ciclos.
// - API pública estable: loadNodesAndConnections / getNodes / getConnections.
// - Compatibilidad: acepta `machines` y `onlyGraph` por constructor (como usa tu SequenceEditorPanel).
//
// NOTA: Este archivo define la clase `Connection` canónica (source/target).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Usa tu entidad real:
import 'package:production_planning/entities/machine_type_entity.dart';

/// ---------------------------------------------------------------------------
/// Arista dirigida del grafo (canónica en el proyecto).
/// - source: id del nodo origen
/// - target: id del nodo destino
/// ---------------------------------------------------------------------------
class Connection {
  final int source;
  final int target;

  const Connection(this.source, this.target);

  Connection copyWith({int? source, int? target}) =>
      Connection(source ?? this.source, target ?? this.target);
}

/// ---------------------------------------------------------------------------
/// Tipos de selección posibles dentro del editor.
/// ---------------------------------------------------------------------------
enum _SelectionType { none, node, edge }

/// ---------------------------------------------------------------------------
/// Estructura de selección actual.
/// - nodeId: id del nodo seleccionado (si aplica)
/// - edgeIndex: índice de la arista seleccionada (si aplica)
/// ---------------------------------------------------------------------------
class _Selection {
  final _SelectionType type;
  final int? nodeId;
  final int? edgeIndex;

  const _Selection._(this.type, {this.nodeId, this.edgeIndex});
  const _Selection.none() : this._(_SelectionType.none);
  const _Selection.node(int id) : this._(_SelectionType.node, nodeId: id);
  const _Selection.edge(int index) : this._(_SelectionType.edge, edgeIndex: index);
}

/// ---------------------------------------------------------------------------
/// Modos de arrastre temporal.
/// ---------------------------------------------------------------------------
enum _DragMode { none, draggingNode, draggingHandleSource, draggingHandleTarget }

/// ---------------------------------------------------------------------------
/// Widget principal del editor de grafo.
/// Acepta `machines` y `onlyGraph` por compatibilidad con SequenceEditorPanel.
/// ---------------------------------------------------------------------------
class NodeEditor extends StatefulWidget {
  /// Lista inicial de máquinas (opcional). Si viene, se dibujan al montar.
  final List<MachineTypeEntity>? machines;

  /// Bandera de "solo grafo" (disponible para quien la necesite; aquí no se usa).
  final bool onlyGraph;

  const NodeEditor({
    super.key,
    this.machines,
    this.onlyGraph = false,
  });

  @override
  State<NodeEditor> createState() => NodeEditorState();
}

class NodeEditorState extends State<NodeEditor> {
  // ==========================
  //   ESTADO DEL GRAFO
  // ==========================

  /// Posición (esquina superior izquierda) de cada nodo por id.
  final Map<int, Offset> _nodePos = {};

  /// Tamaño de cada nodo dibujado (rectángulo).
  static const Size _nodeSize = Size(140, 60);

  /// Entidad de máquina por id (usamos el tipo real del proyecto).
  final Map<int, MachineTypeEntity> _machineById = {};

  /// Lista de aristas dirigidas (source -> target).
  final List<Connection> _connections = [];

  /// Selección (nodo o arista).
  _Selection _sel = const _Selection.none();

  /// Modo de arrastre activo (nodo o handles).
  _DragMode _dragMode = _DragMode.none;

  /// Tap-to-connect: id del nodo origen en preparación.
  int? _connectingFrom;

  /// Posición del cursor (para dibujar flecha temporal).
  Offset? _cursor;

  /// Índice de la arista que se está retocando al arrastrar un handle.
  int? _dragEdgeIndex;

  /// Foco (necesario para que Esc funcione).
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant NodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si cambió la lista de máquinas que llegan por arriba, recargamos
    // manteniendo las conexiones actuales (si existen).
    if (widget.machines != oldWidget.machines && widget.machines != null) {
      loadNodesAndConnections(widget.machines!, _connections);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // ==============================================================
  //   API PÚBLICA (SE MANTIENE PARA NO ROMPER FLUJO DE GUARDADO)
  // ==============================================================

  /// Carga nodos (máquinas) y conexiones.
  /// - [machines]: lista de entidades con al menos `id` (int) y opcionalmente `name` (String).
  /// - [connections]: lista de aristas dirigidas (source -> target).
  void loadNodesAndConnections(
      List<MachineTypeEntity> machines,
      List<Connection> connections,
      ) {
    setState(() {
      _nodePos.clear();
      _machineById.clear();
      _connections
        ..clear()
        ..addAll(connections);

      // Layout inicial simple en grilla:
      final cols = math.max(1, (machines.length / 3.0).ceil());
      const dx = 220.0, dy = 140.0;
      int i = 0;
      for (final m in machines) {
        final id = _extractId(m);
        _machineById[id] = m;
        final col = i % cols;
        final row = (i / cols).floor();
        _nodePos[id] = Offset(120 + col * dx, 120 + row * dy);
        i++;
      }

      _clearTransient();
    });
  }

  /// Retorna las entidades de máquina presentes (para persistencia).
  List<MachineTypeEntity> getNodes() => _machineById.values.toList();

  /// Retorna las conexiones actuales (copia defensiva para evitar problemas al guardar).
  List<Connection> getConnections() {
    // Limpiar estados transitorios antes de retornar
    _clearTransientBeforeSave();
    return List.unmodifiable(_connections);
  }

  /// Limpia estados transitorios antes de guardar para evitar inconsistencias.
  void _clearTransientBeforeSave() {
    if (_dragMode != _DragMode.none ||
        _connectingFrom != null ||
        _cursor != null) {
      setState(() {
        _dragMode = _DragMode.none;
        _connectingFrom = null;
        _cursor = null;
        _dragEdgeIndex = null;
      });
    }
  }

  /// Compat: algunos flujos llaman a esto para agregar un nodo suelto.
  /// - Si `position` no se indica, se ubica en la siguiente celda de una grilla simple.
  void addNodeForMachine(MachineTypeEntity m, {Offset? position}) {
    final id = _extractId(m);
    if (_machineById.containsKey(id)) return; // ya existe
    setState(() {
      _machineById[id] = m;

      // Posición por defecto: siguiente hueco en una grilla de 3 filas aprox.
      final count = _machineById.length - 1; // índice del nuevo
      const dx = 220.0, dy = 140.0;
      final cols = math.max(1, ((_machineById.length) / 3.0).ceil());
      final col = count % cols;
      final row = (count / cols).floor();
      _nodePos[id] = position ?? Offset(120 + col * dx, 120 + row * dy);
    });
  }

  // =======================================
  //   INTERACCIÓN: TAP, DRAG, TECLADO
  // =======================================

  /// Tap en canvas vacío: cancela conexión en preparación o limpia selección.
  void _onTapCanvas() {
    setState(() {
      _cursor = null;                // <-- limpiar la guía
      if (_connectingFrom != null) {
        _connectingFrom = null;      // cancelar tap-to-connect
      } else {
        _sel = const _Selection.none();
      }
    });
  }

  /// Tap en un nodo:
  /// - Si no hay conexión en preparación, inicia tap-to-connect.
  /// - Si ya hay origen, intenta crear source->id (validando DAG).
  void _onTapNode(int id) {
    setState(() {
      if (_connectingFrom == null) {
        _connectingFrom = id;
        _sel = _Selection.node(id);

      } else {
        final from = _connectingFrom!;
        final to = id;
        if (from != to && !_hasEdge(from, to)) {
          if (!_wouldCreateCycle(from, to)) {
            _connections.add(Connection(from, to));
          } else {
            _flashWarn(context, 'Esa conexión crearía un ciclo');
          }
        }
        _connectingFrom = null;
        _cursor = null;              // <-- importante: limpiar al salir del modo conectar
        _sel = _Selection.node(id);
      }
    });
  }

  /// Selección de arista (por índice) para mostrar handles.
  void _onSelectEdge(int edgeIndex) {
    setState(() {
      _sel = _Selection.edge(edgeIndex);
      _cursor = null;                // <-- no mostrar guía si solo está seleccionada
    });
  }

  /// Inicio de drag sobre un nodo.
  void _startDragNode(int id) {
    setState(() {
      _sel = _Selection.node(id);
      _dragMode = _DragMode.draggingNode;
    });
  }

  /// Actualización de drag de nodo (se suma el delta).
  void _updateDragNode(Offset delta) {
    if (_dragMode != _DragMode.draggingNode) return;
    final id = _sel.nodeId!;
    setState(() {
      final p = _nodePos[id]!;
      _nodePos[id] = p + delta;
    });
  }

  /// Fin de drag de nodo.
  void _endDragNode() {
    if (_dragMode == _DragMode.draggingNode) {
      setState(() => _dragMode = _DragMode.none);
    }
  }

  /// Inicio de drag del handle de ORIGEN de una arista.
  void _startDragHandleSource(int edgeIndex) {
    setState(() {
      _dragMode = _DragMode.draggingHandleSource;
      _dragEdgeIndex = edgeIndex;
    });
  }

  /// Inicio de drag del handle de DESTINO de una arista.
  void _startDragHandleTarget(int edgeIndex) {
    setState(() {
      _dragMode = _DragMode.draggingHandleTarget;
      _dragEdgeIndex = edgeIndex;
    });
  }

  /// Durante drag de handle, actualizamos `_cursor` para previsualizar la flecha.
  void _updateDragHandle(Offset cursor) {
    if (_dragMode == _DragMode.draggingHandleSource ||
        _dragMode == _DragMode.draggingHandleTarget) {
      setState(() => _cursor = cursor);
    }
  }

  /// Fin de drag de handle: si suelta sobre nodo, reasigna source/target (validando DAG).
  void _endDragHandle() {
    if (_dragEdgeIndex == null) {
      setState(() {
        _dragMode = _DragMode.none;
        _cursor = null;
      });
      return;
    }
    final idx = _dragEdgeIndex!;
    final hit = _hitNodeAt(_cursor);
    if (hit != null) {
      final e = _connections[idx];
      final newConn = (_dragMode == _DragMode.draggingHandleSource)
          ? e.copyWith(source: hit)
          : e.copyWith(target: hit);

      if (newConn.source == newConn.target) {
        _flashWarn(context, 'No se permiten autolazos');
      } else if (_hasEdge(newConn.source, newConn.target, ignoreIndex: idx)) {
        // Ya existe esa conexión exacta (ignorando la propia).
      } else if (_wouldCreateCycle(newConn.source, newConn.target, ignoreIndex: idx)) {
        _flashWarn(context, 'Esa reasignación crea un ciclo');
      } else {
        setState(() => _connections[idx] = newConn);
      }
    }
    setState(() {
      _dragMode = _DragMode.none;
      _dragEdgeIndex = null;
      _cursor = null;
    });
  }

  // =======================================
  //   TECLADO: ESC PARA ELIMINAR
  // =======================================

  /// Atajo: Supr/Delete/Backspace -> borrar selección.
  Map<ShortcutActivator, Intent> get _shortcuts => {
    // Supr (Delete) borra nodo/arista seleccionada
    const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
    // Backspace como alternativa (algunos teclados)
    const SingleActivator(LogicalKeyboardKey.backspace): const _DeleteIntent(),
  };
  /// Acción asociada a Supr.
  Map<Type, Action<Intent>> get _actions => {
    _DeleteIntent: CallbackAction<_DeleteIntent>(onInvoke: (intent) {
      _deleteSelection();
      return null;
    })
  };

  /// Borrado de selección:
  /// - Nodo: elimina el nodo y sus aristas incidentes.
  /// - Arista: elimina solo esa arista.
  void _deleteSelection() {
    if (_sel.type == _SelectionType.none) return;

    setState(() {
      switch (_sel.type) {
        case _SelectionType.none:
          return;
        case _SelectionType.node:
          final id = _sel.nodeId;
          if (id == null) return;

          // Verificar que el nodo existe antes de eliminarlo
          if (!_nodePos.containsKey(id)) return;

          _nodePos.remove(id);
          _machineById.remove(id);
          _connections.removeWhere((e) => e.source == id || e.target == id);
          _sel = const _Selection.none();
          _connectingFrom = null;
          _cursor = null;
          break;

        case _SelectionType.edge:
          final idx = _sel.edgeIndex;
          if (idx == null || idx < 0 || idx >= _connections.length) return;

          _connections.removeAt(idx);
          _sel = const _Selection.none();
          _cursor = null;
          break;
      }
    });
  }

  // =======================================
  //   UTILIDADES DE GRAFO (DAG)
  // =======================================

  /// ¿Existe ya la arista source->target? (opcionalmente ignorando una por índice).
  bool _hasEdge(int source, int target, {int? ignoreIndex}) {
    for (var i = 0; i < _connections.length; i++) {
      if (ignoreIndex != null && i == ignoreIndex) continue;
      final e = _connections[i];
      if (e.source == source && e.target == target) return true;
    }
    return false;
  }

  /// Verifica si agregar/reasignar (from->to) crearía un ciclo.
  /// Estrategia: comprobar si ya existe un camino to -> from en el grafo.
  bool _wouldCreateCycle(int from, int to, {int? ignoreIndex}) {
    final adj = <int, Set<int>>{};
    for (var i = 0; i < _connections.length; i++) {
      if (ignoreIndex != null && i == ignoreIndex) continue;
      final e = _connections[i];
      adj.putIfAbsent(e.source, () => <int>{}).add(e.target);
    }
    adj.putIfAbsent(from, () => <int>{}).add(to); // simular nueva arista
    return _reachable(adj, to, from);
  }

  /// DFS iterativo para saber si dst es alcanzable desde src.
  bool _reachable(Map<int, Set<int>> adj, int src, int dst) {
    final seen = <int>{};
    final stack = <int>[src];
    while (stack.isNotEmpty) {
      final v = stack.removeLast();
      if (v == dst) return true;
      if (!seen.add(v)) continue;
      final ns = adj[v];
      if (ns != null) stack.addAll(ns);
    }
    return false;
  }

  /// Devuelve el id de un nodo bajo el punto p (si hay).
  int? _hitNodeAt(Offset? p) {
    if (p == null) return null;
    for (final entry in _nodePos.entries) {
      final id = entry.key;
      final rect = _nodeRect(id);
      if (rect.contains(p)) return id;
    }
    return null;
  }

  /// Rectángulo de un nodo por id.
  Rect _nodeRect(int id) {
    final pos = _nodePos[id]!;
    return Rect.fromLTWH(pos.dx, pos.dy, _nodeSize.width, _nodeSize.height);
  }

  // =======================================
  //   WIDGET / RENDERIZADO
  // =======================================

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          focusNode: _focusNode,
          autofocus: true, // para que Esc funcione sin clicks previos
          child: GestureDetector(
            behavior: HitTestBehavior.opaque, // IMPORTANTE: captura todos los eventos
             onTap: () {
            // Recuperar el foco al hacer clic en cualquier parte
             if (!_focusNode.hasFocus) {
            _focusNode.requestFocus();
              }
            },
          child: MouseRegion(
            onHover: (e) {
              final isConnecting = _connectingFrom != null;
              final isDraggingHandle = _dragMode == _DragMode.draggingHandleSource ||
                  _dragMode == _DragMode.draggingHandleTarget;

              if (isConnecting || isDraggingHandle) {
                if (_cursor != e.localPosition) {
                  setState(() => _cursor = e.localPosition);
                }
              } else if (_cursor != null) {
                setState(() => _cursor = null);  // <-- evita que quede una guía “fantasma”
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Lienzo amplio para permitir mover con comodidad
                final canvasSize = Size(
                  math.max(constraints.maxWidth, 1200),
                  math.max(constraints.maxHeight, 800),
                );
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (d) {
                    // 1) ¿clic cerca de una arista? -> selección de arista
                    final edgeIdx = _hitEdge(d.localPosition);
                    if (edgeIdx != null) {
                      _onSelectEdge(edgeIdx);
                      return;
                    }
                    // 2) ¿clic sobre un nodo? -> tap-to-connect / seleccionar
                    final nodeId = _hitNodeAt(d.localPosition);
                    if (nodeId != null) {
                      _onTapNode(nodeId);
                      return;
                    }
                    // 3) canvas vacío
                    _onTapCanvas();
                  },
                  onPanStart: (d) {
                    // ¿Arranca sobre handle de arista seleccionada?
                    if (_sel.type == _SelectionType.edge) {
                      final idx = _sel.edgeIndex!;
                      final handles = _edgeHandles(idx);
                      if ((handles.$1 - d.localPosition).distance <= 10) {
                        _startDragHandleSource(idx);
                        return;
                      }
                      if ((handles.$2 - d.localPosition).distance <= 10) {
                        _startDragHandleTarget(idx);
                        return;
                      }
                    }
                    // ¿Arranca sobre un nodo? -> drag de nodo
                    final nodeId = _hitNodeAt(d.localPosition);
                    if (nodeId != null) {
                      _startDragNode(nodeId);
                      return;
                    }
                  },
                  onPanUpdate: (d) {
                    switch (_dragMode) {
                      case _DragMode.draggingNode:
                        _updateDragNode(d.delta);
                        break;
                      case _DragMode.draggingHandleSource:
                      case _DragMode.draggingHandleTarget:
                        _updateDragHandle(d.localPosition);
                        break;
                      case _DragMode.none:
                        break;
                    }
                  },
                  onPanEnd: (d) {
                    switch (_dragMode) {
                      case _DragMode.draggingNode:
                        _endDragNode();
                        break;
                      case _DragMode.draggingHandleSource:
                      case _DragMode.draggingHandleTarget:
                        _endDragHandle();
                        break;
                      case _DragMode.none:
                        break;
                    }
                  },
                  child: CustomPaint(
                    painter: _GraphPainter(
                      nodePos: _nodePos,
                      nodeSize: _nodeSize,
                      connections: _connections,
                      selection: _sel,
                      connectingFrom: _connectingFrom,
                      cursor: _cursor,
                      machineById: _machineById,
                      isDraggingHandle: _dragMode == _DragMode.draggingHandleSource ||
                          _dragMode == _DragMode.draggingHandleTarget,
                      draggingEdgeIndex: _dragEdgeIndex,
                      draggingHandleIsSource: _dragMode == _DragMode.draggingHandleSource,
                    ),
                    size: canvasSize,
                  ),

                );
              },
            ),
          ),
          ),
        ),
      ),
    );
  }

  /// Hit-test de aristas: devuelve índice si el punto está "cerca" del segmento.
  int? _hitEdge(Offset p) {
    const threshold = 8.0; // tolerancia de clic sobre línea
    for (var i = 0; i < _connections.length; i++) {
      final e = _connections[i];
      final a = _nodeCenter(e.source);
      final b = _nodeCenter(e.target);
      // Anclar a los bordes exactos del rectángulo del nodo
      final from = _shrinkToRectEdge(a, b, _nodeRect(e.source));
      final to = _shrinkToRectEdge(b, a, _nodeRect(e.target));
      final d = _distancePointToSegment(p, from, to);
      if (d <= threshold) return i;
    }
    return null;
  }

  /// Centro geométrico de un rectángulo de nodo.
  Offset _nodeCenter(int id) {
    final r = _nodeRect(id);
    return Offset(r.left + r.width / 2, r.top + r.height / 2);
  }

  /// Intersección del segmento [from->toward] con el borde del rectángulo `rect`.
  /// Sirve para que la línea toque exactamente el borde del nodo.
  Offset _shrinkToRectEdge(Offset from, Offset toward, Rect rect) {
    final dir = (from - toward);
    if (dir.distance < 1e-6) return from;
    final candidates = <Offset>[];
    final lines = <(Offset, Offset)>[
      (Offset(rect.left, rect.top), Offset(rect.right, rect.top)),       // top
      (Offset(rect.left, rect.bottom), Offset(rect.right, rect.bottom)), // bottom
      (Offset(rect.left, rect.top), Offset(rect.left, rect.bottom)),     // left
      (Offset(rect.right, rect.top), Offset(rect.right, rect.bottom)),   // right
    ];
    for (final seg in lines) {
      final p = _segmentIntersection(from, toward, seg.$1, seg.$2);
      if (p != null) candidates.add(p);
    }
    if (candidates.isEmpty) return from;
    candidates.sort((a, b) => (a - from).distance.compareTo((b - from).distance));
    return candidates.first;
  }

  /// Intersección de dos segmentos (p1-p2) y (p3-p4). Null si no se cortan.
  Offset? _segmentIntersection(Offset p1, Offset p2, Offset p3, Offset p4) {
    final x1 = p1.dx, y1 = p1.dy;
    final x2 = p2.dx, y2 = p2.dy;
    final x3 = p3.dx, y3 = p3.dy;
    final x4 = p4.dx, y4 = p4.dy;

    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-9) return null;

    final det1 = x1 * y2 - y1 * x2;
    final det2 = x3 * y4 - y3 * x4;
    final px = (det1 * (x3 - x4) - (x1 - x2) * det2) / denom;
    final py = (det1 * (y3 - y4) - (y1 - y2) * det2) / denom;
    final p = Offset(px, py);

    bool onSeg(Offset a, Offset b, Offset p) {
      final minX = math.min(a.dx, b.dx) - 1e-6, maxX = math.max(a.dx, b.dx) + 1e-6;
      final minY = math.min(a.dy, b.dy) - 1e-6, maxY = math.max(a.dy, b.dy) + 1e-6;
      return p.dx >= minX && p.dx <= maxX && p.dy >= minY && p.dy <= maxY;
    }

    if (onSeg(p1, p2, p) && onSeg(p3, p4, p)) return p;
    return null;
  }

  /// Distancia del punto `p` al segmento `a-b` (para hit-test de aristas).
  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final ap = p - a;
    final ab = b - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (ab2 == 0) return (p - a).distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / ab2).clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  /// Coordenadas de los handles (círculos) en los extremos de una arista seleccionada.
  (Offset, Offset) _edgeHandles(int edgeIndex) {
    final e = _connections[edgeIndex];
    final a = _nodeCenter(e.source);
    final b = _nodeCenter(e.target);
    final from = _shrinkToRectEdge(a, b, _nodeRect(e.source));
    final to = _shrinkToRectEdge(b, a, _nodeRect(e.target));
    return (from, to);
  }

  /// Limpia estados transitorios (selección, drags, conexión en preparación).
  void _clearTransient() {
    _sel = const _Selection.none();
    _dragMode = _DragMode.none;
    _connectingFrom = null;
    _dragEdgeIndex = null;
    _cursor = null;
  }

  // ==========================
  //   LECTURA DE ENTIDADES
  // ==========================

  /// Extrae el id desde tu entidad (ajústalo si se llama distinto).
  int _extractId(MachineTypeEntity m) {
    final dynamic raw = (m as dynamic).id; // admite int?, String?, etc.
    if (raw == null) {
      throw StateError('MachineTypeEntity.id es null');
    }
    if (raw is int) return raw;
    // Si el id llega como String u otro tipo numérico
    return int.parse(raw.toString());
  }

  /// Un label legible para pintar dentro del nodo.
  /// Ajusta si tu entidad expone otro campo (p.ej., `m.machineName`).
  String _extractLabel(MachineTypeEntity m) {
    try {
      // Si tu clase tiene 'name' opcional:
      final nameField = (m as dynamic).name;
      if (nameField is String && nameField.isNotEmpty) return nameField;
    } catch (_) {
      // Ignora si no existe el campo 'name'
    }
    return 'Nodo ${m.id}';
  }

  /// SnackBar corto de advertencia (e.g., intento de crear ciclo).
  void _flashWarn(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

/// ---------------------------------------------------------------------------
/// Painter del grafo: grilla, aristas, flecha temporal y nodos.
/// ---------------------------------------------------------------------------
class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodePos,
    required this.nodeSize,
    required this.connections,
    required this.selection,
    required this.connectingFrom,
    required this.cursor,
    required this.machineById,
    // NUEVO:
    required this.isDraggingHandle,
    required this.draggingEdgeIndex,
    required this.draggingHandleIsSource,
  });

  final Map<int, Offset> nodePos;
  final Size nodeSize;
  final List<Connection> connections;
  final _Selection selection;
  final int? connectingFrom;
  final Offset? cursor;
  final Map<int, MachineTypeEntity> machineById;

  // NUEVO:
  final bool isDraggingHandle;
  final int? draggingEdgeIndex;
  final bool draggingHandleIsSource;

  @override
  void paint(Canvas canvas, Size size) {
    // (1) Grilla de fondo
    _drawGrid(canvas, size);

    // (2) Aristas (líneas rectas con flecha)
    for (var i = 0; i < connections.length; i++) {
      // NUEVO: si estamos arrastrando el handle de ESTA arista, no pintes la línea sólida
      if (isDraggingHandle && draggingEdgeIndex == i) {
        continue;
      }

      final e = connections[i];
      final fromRect = _nodeRect(e.source);
      final toRect = _nodeRect(e.target);

      final a = _center(fromRect);
      final b = _center(toRect);

      // Anclar a los bordes del rectángulo (más prolijo que al centro)
      final p1 = _shrinkToRectEdge(a, b, fromRect);
      final p2 = _shrinkToRectEdge(b, a, toRect);

      final selected = selection.type == _SelectionType.edge && selection.edgeIndex == i;
      _drawArrow(canvas, p1, p2, selected: selected);

    }

    // (3) Handles en extremos de la arista seleccionada
    if (selection.type == _SelectionType.edge) {
      final idx = selection.edgeIndex!;
      final e = connections[idx];
      final p1 = _shrinkToRectEdge(
          _center(_nodeRect(e.source)), _center(_nodeRect(e.target)), _nodeRect(e.source));
      final p2 = _shrinkToRectEdge(
          _center(_nodeRect(e.target)), _center(_nodeRect(e.source)), _nodeRect(e.target));
      final paint = Paint()..color = Colors.blue;
      canvas.drawCircle(p1, 6, paint);
      canvas.drawCircle(p2, 6, paint);
    }

    // (4) Flecha temporal
    //  a) durante tap-to-connect
    //  b) durante arrastre de handle (preview)
    // Flecha temporal (a) tap-to-connect  (b) arrastre de handle
    if (connectingFrom != null && cursor != null) {
      final fromRect = _nodeRect(connectingFrom!);
      final a = _center(fromRect);
      final p1 = _shrinkToRectEdge(a, cursor!, fromRect);
      _drawArrow(canvas, p1, cursor!, dashed: true);
    } else if (isDraggingHandle && cursor != null && draggingEdgeIndex != null) {
      // NUEVO: preview de la arista que estamos editando
      final e = connections[draggingEdgeIndex!];
      final fromRect = _nodeRect(e.source);
      final toRect   = _nodeRect(e.target);
      final from = _shrinkToRectEdge(_center(fromRect), _center(toRect), fromRect);
      final to   = _shrinkToRectEdge(_center(toRect), _center(fromRect), toRect);

      if (draggingHandleIsSource) {
        // Mueves el ORIGEN: cursor -> to
        _drawArrow(canvas, cursor!, to, dashed: true);
      } else {
        // Mueves el DESTINO: from -> cursor
        _drawArrow(canvas, from, cursor!, dashed: true);
      }
    }


    // (5) Nodos (rectángulos con etiqueta)
    for (final entry in nodePos.entries) {
      final id = entry.key;
      final pos = entry.value;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, nodeSize.width, nodeSize.height);
      final isSel = selection.type == _SelectionType.node && selection.nodeId == id;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      final fill = Paint()..color = isSel ? Colors.blue.shade100 : Colors.white;
      final stroke = Paint()
        ..color = isSel ? Colors.blue : Colors.grey.shade600
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 2.4 : 1.2;

      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);

      final label = _extractLabel(machineById[id]!);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 13,
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: nodeSize.width - 16);

      final labelOffset = Offset(
        rect.left + 8,
        rect.top + (rect.height - tp.height) / 2,
      );
      tp.paint(canvas, labelOffset);
    }
  }

  /// Grilla liviana de fondo.
  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  /// Rect de un nodo por id (según estado actual).
  Rect _nodeRect(int id) {
    final pos = nodePos[id]!;
    return Rect.fromLTWH(pos.dx, pos.dy, nodeSize.width, nodeSize.height);
  }

  /// Centro geométrico de un rect.
  Offset _center(Rect r) => Offset(r.left + r.width / 2, r.top + r.height / 2);

  /// Intersección del segmento [from->toward] con los bordes del rectángulo.
  Offset _shrinkToRectEdge(Offset from, Offset toward, Rect rect) {
    final candidates = <Offset>[];
    final edges = <(Offset, Offset)>[
      (Offset(rect.left, rect.top), Offset(rect.right, rect.top)),
      (Offset(rect.right, rect.top), Offset(rect.right, rect.bottom)),
      (Offset(rect.right, rect.bottom), Offset(rect.left, rect.bottom)),
      (Offset(rect.left, rect.bottom), Offset(rect.left, rect.top)),
    ];
    for (final e in edges) {
      final p = _segmentIntersection(from, toward, e.$1, e.$2);
      if (p != null) candidates.add(p);
    }
    if (candidates.isEmpty) return from;
    candidates.sort((a, b) => (a - from).distance.compareTo((b - from).distance));
    return candidates.first;
  }

  /// Intersección de segmentos; null si no intersectan.
  Offset? _segmentIntersection(Offset p1, Offset p2, Offset p3, Offset p4) {
    final x1 = p1.dx, y1 = p1.dy;
    final x2 = p2.dx, y2 = p2.dy;
    final x3 = p3.dx, y3 = p3.dy;
    final x4 = p4.dx, y4 = p4.dy;
    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-9) return null;

    final det1 = x1 * y2 - y1 * x2;
    final det2 = x3 * y4 - y3 * x4;
    final px = (det1 * (x3 - x4) - (x1 - x2) * det2) / denom;
    final py = (det1 * (y3 - y4) - (y1 - y2) * det2) / denom;
    final p = Offset(px, py);

    bool onSeg(Offset a, Offset b, Offset p) {
      final minX = math.min(a.dx, b.dx) - 1e-6, maxX = math.max(a.dx, b.dx) + 1e-6;
      final minY = math.min(a.dy, b.dy) - 1e-6, maxY = math.max(a.dy, b.dy) + 1e-6;
      return p.dx >= minX && p.dx <= maxX && p.dy >= minY && p.dy <= maxY;
    }

    if (onSeg(p1, p2, p) && onSeg(p3, p4, p)) return p;
    return null;
  }

  /// Dibuja flecha (línea + triángulo). `dashed` para guías/preview; `selected` resalta.
  void _drawArrow(Canvas canvas, Offset from, Offset to,
      {bool dashed = false, bool selected = false}) {
    final paint = Paint()
      ..color = selected ? Colors.blue : Colors.black87
      ..strokeWidth = selected ? 2.5 : 1.6
      ..style = PaintingStyle.stroke;

    if (!dashed) {
      canvas.drawLine(from, to, paint);
    } else {
      const dash = 8.0, gap = 6.0;
      final total = (to - from).distance;
      final dir = (to - from) / total;
      double t = 0;
      while (t < total) {
        final p1 = from + dir * t;
        final p2 = from + dir * math.min(t + dash, total);
        canvas.drawLine(p1, p2, paint);
        t += dash + gap;
      }
    }

    // Triángulo de flecha en el extremo "to"
    final v = (to - from);
    final len = v.distance;
    if (len < 1e-6) return;
    final u = v / len;
    const arrowLen = 12.0, arrowWidth = 5.5;
    final tip = to;
    final left = tip - u * arrowLen + Offset(-u.dy, u.dx) * arrowWidth;
    final right = tip - u * arrowLen + Offset(u.dy, -u.dx) * arrowWidth;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    final fill = Paint()
      ..color = selected ? Colors.blue : Colors.black87
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fill);
  }

  /// Extrae un label legible desde la entidad (usa `name` si existe).
  String _extractLabel(MachineTypeEntity m) {
    try {
      final nameField = (m as dynamic).name;
      if (nameField is String && nameField.isNotEmpty) return nameField;
    } catch (_) {}
    return 'Nodo ${m.id}';
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) {
    // Re-pintar al cambiar nodos, conexiones o estados transitorios/selección.
    return old.nodePos != nodePos ||
        old.connections != connections ||
        old.selection.type != selection.type ||
        old.selection.nodeId != selection.nodeId ||
        old.selection.edgeIndex != selection.edgeIndex ||
        old.connectingFrom != connectingFrom ||
        old.cursor != cursor ||
        old.machineById.length != machineById.length;
  }
}

/// Intent interno para borrar con Supr.
class _DeleteIntent extends Intent {
  const _DeleteIntent();
}
