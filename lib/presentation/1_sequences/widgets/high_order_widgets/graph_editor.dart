// widgets/high_order_widgets/graph_editor.dart
//
// Editor de grafo para rutas de proceso (Flutter desktop).
//
// - Cada nodo es una TAREA de la ruta (RouteNode); las flechas van de tarea
//   a tarea.
// - Barra de herramientas: Seleccionar / Conectar, Eliminar, Ordenar,
//   Ver todo y zoom.
// - Seleccionar: clic selecciona nodo o flecha; arrastrar mueve el nodo;
//   arrastrar el fondo desplaza la vista; la rueda del ratón hace zoom.
// - Conectar: clic en el origen y luego en el destino. Si ya había una
//   estación seleccionada, la flecha sale de ella. Esc cancela.
// - Ordenar: columnas por precedencia, sin cruces de flechas cuando es
//   posible (ver layeredLayout); las flechas largas pasan por puntos
//   intermedios.
// - Supr / Retroceso borran la selección. No se permiten ciclos ni autolazos.
// - [NodeEditor.readOnly]: solo se puede mirar (desplazar y hacer zoom).
//
// Todas las posiciones se guardan en coordenadas del "mundo"; la vista
// aplica una escala y un desplazamiento propios.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/entities/route_draft.dart';

enum _SelectionType { none, node, edge }

class _Selection {
  final _SelectionType type;
  final int? nodeKey;
  final int? edgeIndex;

  const _Selection._(this.type, {this.nodeKey, this.edgeIndex});
  const _Selection.none() : this._(_SelectionType.none);
  const _Selection.node(int key) : this._(_SelectionType.node, nodeKey: key);
  const _Selection.edge(int index)
      : this._(_SelectionType.edge, edgeIndex: index);
}

enum _DragMode { none, node, handleSource, handleTarget, pan }

/// Herramienta activa de la barra.
enum EditorTool { select, connect }

class NodeEditor extends StatefulWidget {
  /// Solo lectura: sin barra de edición ni panel; se puede desplazar y hacer
  /// zoom para mirar la ruta.
  final bool readOnly;

  /// Route shown when the editor is built. To show another route, build a
  /// new editor (give it a different key).
  final RouteDraft? initialDraft;

  const NodeEditor({super.key, this.readOnly = false, this.initialDraft});

  @override
  State<NodeEditor> createState() => NodeEditorState();
}

class NodeEditorState extends State<NodeEditor> {
  static const Size _nodeSize = Size(150, 64);
  static const double _minScale = 0.3;
  static const double _maxScale = 2.0;

  // ── Grafo ────────────────────────────────────────────────────────────────
  final Map<int, RouteNode> _nodes = {}; // conserva el orden de inserción
  final Map<int, Offset> _pos = {}; // esquina superior izquierda, mundo
  final List<RouteArrow> _arrows = [];

  /// Waypoints of the arrows that skip columns, set by Ordenar
  /// ([layeredLayout]). An arrow loses them as soon as one of its ends
  /// moves, and is drawn straight again.
  final Map<RouteArrow, List<Offset>> _bends = {};
  int _nextKey = -1;

  // ── Interacción ──────────────────────────────────────────────────────────
  EditorTool _tool = EditorTool.select;
  _Selection _sel = const _Selection.none();
  _DragMode _drag = _DragMode.none;
  int? _connectingFrom;
  Offset? _cursor; // mundo
  int? _dragEdgeIndex;

  // ── Vista ────────────────────────────────────────────────────────────────
  double _scale = 1.0;
  Offset _pan = Offset.zero;
  Size _viewport = Size.zero;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.initialDraft != null) {
      _applyDraft(widget.initialDraft!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fitView();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // ==============================================================
  //   API PÚBLICA
  // ==============================================================

  /// Carga una ruta y la acomoda por niveles.
  void loadDraft(RouteDraft draft) {
    setState(() => _applyDraft(draft));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fitView();
    });
  }

  void _applyDraft(RouteDraft draft) {
    _nodes.clear();
    _pos.clear();
    _arrows
      ..clear()
      ..addAll(draft.arrows);
    for (final n in draft.nodes) {
      _nodes[n.key] = n.copy();
    }
    _nextKey = math.min(-1, _nodes.keys.fold<int>(0, math.min) - 1);
    _applyLayout();
    _clearTransient();
  }

  void _applyLayout() {
    final layout = layeredLayout(_nodes.keys.toList(), _arrows,
        nodeWidth: _nodeSize.width, nodeHeight: _nodeSize.height);
    _pos
      ..clear()
      ..addAll(layout.positions);
    _bends
      ..clear()
      ..addAll(layout.bends);
  }

  void clear() => loadDraft(const RouteDraft(name: ''));

  /// Las tareas actuales, en el orden en que se agregaron.
  List<RouteNode> currentNodes() =>
      [for (final n in _nodes.values) n.copy()];

  List<RouteArrow> currentArrows() => List.unmodifiable(_arrows);

  /// Agrega una estación como nueva tarea, a la derecha de lo que ya hay.
  /// Devuelve false (y avisa) si la estación ya está en la ruta.
  bool addStation(MachineTypeEntity station) {
    if (widget.readOnly || station.id == null) return false;
    if (_nodes.values.any((n) => n.machineTypeId == station.id)) {
      _flashWarn('La estación "${station.name}" ya está en la ruta');
      return false;
    }
    final key = _nextKey--;
    setState(() {
      _nodes[key] = RouteNode(
        key: key,
        machineTypeId: station.id!,
        machineName: station.name,
      );
      _pos[key] = _nextFreePosition();
      _sel = _Selection.node(key);
    });
    _ensureVisible(key);
    return true;
  }

  // ==============================================================
  //   ACCIONES DE LA BARRA
  // ==============================================================

  void _setTool(EditorTool tool) {
    setState(() {
      _tool = tool;
      _cursor = null;
      // With a station already selected, Conectar starts the arrow from it:
      // the next click only has to pick the destination.
      _connectingFrom =
          tool == EditorTool.connect && _sel.type == _SelectionType.node
              ? _sel.nodeKey
              : null;
    });
  }

  void autoLayout() {
    setState(_applyLayout);
    fitView();
  }

  /// Ajusta escala y desplazamiento para que quepa toda la ruta.
  void fitView() {
    if (_viewport == Size.zero) return;
    if (_nodes.isEmpty) {
      setState(() {
        _scale = 1;
        _pan = Offset.zero;
      });
      return;
    }
    final box = _boundingBox().inflate(40);
    final scale = math
        .min(_viewport.width / box.width, _viewport.height / box.height)
        .clamp(_minScale, 1.2)
        .toDouble();
    setState(() {
      _scale = scale;
      _pan = Offset(
        (_viewport.width - box.width * scale) / 2 - box.left * scale,
        (_viewport.height - box.height * scale) / 2 - box.top * scale,
      );
    });
  }

  void _zoomBy(double factor, {Offset? focus}) {
    final f = focus ?? _viewport.center(Offset.zero);
    final newScale = (_scale * factor).clamp(_minScale, _maxScale).toDouble();
    final world = _toWorld(f);
    setState(() {
      _scale = newScale;
      _pan = f - world * newScale;
    });
  }

  void _deleteSelection() {
    if (widget.readOnly) return;
    setState(() {
      switch (_sel.type) {
        case _SelectionType.none:
          return;
        case _SelectionType.node:
          final key = _sel.nodeKey!;
          _nodes.remove(key);
          _pos.remove(key);
          _arrows.removeWhere((a) => a.from == key || a.to == key);
          _bends.removeWhere((a, _) => a.from == key || a.to == key);
        case _SelectionType.edge:
          final idx = _sel.edgeIndex!;
          if (idx >= 0 && idx < _arrows.length) {
            _bends.remove(_arrows.removeAt(idx));
          }
      }
      _clearTransient();
    });
  }

  // ==============================================================
  //   INTERACCIÓN
  // ==============================================================

  Offset _toWorld(Offset local) => (local - _pan) / _scale;

  void _onTapDown(Offset local) {
    _focusNode.requestFocus();
    if (widget.readOnly) return;
    final p = _toWorld(local);

    final nodeKey = _hitNode(p);
    if (_tool == EditorTool.connect) {
      setState(() {
        if (nodeKey == null) {
          _connectingFrom = null;
          _cursor = null;
        } else if (_connectingFrom == null) {
          _connectingFrom = nodeKey;
          _sel = _Selection.node(nodeKey);
        } else {
          _tryConnect(_connectingFrom!, nodeKey);
          _connectingFrom = null;
          _cursor = null;
        }
      });
      return;
    }

    final edge = nodeKey == null ? _hitEdge(p) : null;
    setState(() {
      if (nodeKey != null) {
        _sel = _Selection.node(nodeKey);
      } else if (edge != null) {
        _sel = _Selection.edge(edge);
      } else {
        _sel = const _Selection.none();
      }
    });
  }

  void _tryConnect(int from, int to) {
    if (from == to) {
      _flashWarn('No se permiten autolazos');
    } else if (_hasEdge(from, to)) {
      // Ya existe.
    } else if (_wouldCreateCycle(from, to)) {
      _flashWarn('Esa conexión crearía un ciclo');
    } else {
      _arrows.add(RouteArrow(from, to));
    }
  }

  void _onPanStart(Offset local) {
    final p = _toWorld(local);
    if (!widget.readOnly && _tool == EditorTool.select) {
      if (_sel.type == _SelectionType.edge) {
        final handles = _edgeHandles(_sel.edgeIndex!);
        final tolerance = 10 / _scale;
        if ((handles.$1 - p).distance <= tolerance) {
          setState(() {
            _drag = _DragMode.handleSource;
            _dragEdgeIndex = _sel.edgeIndex;
          });
          return;
        }
        if ((handles.$2 - p).distance <= tolerance) {
          setState(() {
            _drag = _DragMode.handleTarget;
            _dragEdgeIndex = _sel.edgeIndex;
          });
          return;
        }
      }
      final nodeKey = _hitNode(p);
      if (nodeKey != null) {
        setState(() {
          _sel = _Selection.node(nodeKey);
          _drag = _DragMode.node;
        });
        return;
      }
    }
    setState(() => _drag = _DragMode.pan);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    switch (_drag) {
      case _DragMode.node:
        final key = _sel.nodeKey!;
        setState(() {
          _pos[key] = _pos[key]! + d.delta / _scale;
          // Its arrows' waypoints no longer fit: draw them straight.
          _bends.removeWhere((a, _) => a.from == key || a.to == key);
        });
      case _DragMode.handleSource:
      case _DragMode.handleTarget:
        setState(() => _cursor = _toWorld(d.localPosition));
      case _DragMode.pan:
        setState(() => _pan += d.delta);
      case _DragMode.none:
        break;
    }
  }

  void _onPanEnd() {
    if (_drag == _DragMode.handleSource || _drag == _DragMode.handleTarget) {
      _endDragHandle();
    }
    setState(() => _drag = _DragMode.none);
  }

  void _endDragHandle() {
    final idx = _dragEdgeIndex;
    final hit = _cursor == null ? null : _hitNode(_cursor!);
    if (idx != null && hit != null) {
      final e = _arrows[idx];
      final updated = _drag == _DragMode.handleSource
          ? RouteArrow(hit, e.to)
          : RouteArrow(e.from, hit);
      if (updated.from == updated.to) {
        _flashWarn('No se permiten autolazos');
      } else if (_hasEdge(updated.from, updated.to, ignoreIndex: idx)) {
        // Ya existe esa conexión.
      } else if (_wouldCreateCycle(updated.from, updated.to,
          ignoreIndex: idx)) {
        _flashWarn('Esa reasignación crea un ciclo');
      } else {
        _bends.remove(_arrows[idx]);
        _arrows[idx] = updated;
      }
    }
    _dragEdgeIndex = null;
    _cursor = null;
  }

  void _onHover(Offset local) {
    if (_connectingFrom != null) {
      setState(() => _cursor = _toWorld(local));
    }
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _zoomBy(e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1, focus: e.localPosition);
    }
  }

  // ==============================================================
  //   UTILIDADES
  // ==============================================================

  bool _hasEdge(int from, int to, {int? ignoreIndex}) {
    for (var i = 0; i < _arrows.length; i++) {
      if (i == ignoreIndex) continue;
      if (_arrows[i].from == from && _arrows[i].to == to) return true;
    }
    return false;
  }

  /// ¿Agregar from → to cerraría un ciclo? Es decir, ¿ya hay camino to → from?
  bool _wouldCreateCycle(int from, int to, {int? ignoreIndex}) {
    final adj = <int, List<int>>{};
    for (var i = 0; i < _arrows.length; i++) {
      if (i == ignoreIndex) continue;
      adj.putIfAbsent(_arrows[i].from, () => []).add(_arrows[i].to);
    }
    final seen = <int>{};
    final stack = <int>[to];
    while (stack.isNotEmpty) {
      final v = stack.removeLast();
      if (v == from) return true;
      if (seen.add(v)) stack.addAll(adj[v] ?? const []);
    }
    return false;
  }

  Rect _nodeRect(int key) => _pos[key]! & _nodeSize;

  int? _hitNode(Offset p) {
    // De arriba hacia abajo: el último dibujado queda encima.
    for (final key in _pos.keys.toList().reversed) {
      if (_nodeRect(key).contains(p)) return key;
    }
    return null;
  }

  int? _hitEdge(Offset p) {
    final threshold = 8 / _scale;
    for (var i = 0; i < _arrows.length; i++) {
      final pts = _arrowPoints(_arrows[i], _pos, _bends, _nodeSize);
      for (var j = 0; j + 1 < pts.length; j++) {
        if (_distanceToSegment(p, pts[j], pts[j + 1]) <= threshold) return i;
      }
    }
    return null;
  }

  (Offset, Offset) _edgeHandles(int index) {
    final pts = _arrowPoints(_arrows[index], _pos, _bends, _nodeSize);
    return (pts.first, pts.last);
  }

  Rect _boundingBox() {
    Rect? box;
    for (final key in _pos.keys) {
      final r = _nodeRect(key);
      box = box == null ? r : box.expandToInclude(r);
    }
    return box ?? Rect.zero;
  }

  Offset _nextFreePosition() {
    if (_pos.isEmpty) return const Offset(60, 60);
    final box = _boundingBox();
    return Offset(box.right + 70, box.top);
  }

  void _ensureVisible(int key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewport == Size.zero || !_pos.containsKey(key)) {
        return;
      }
      final r = _nodeRect(key);
      final screen = Rect.fromPoints(
          r.topLeft * _scale + _pan, r.bottomRight * _scale + _pan);
      final view = Offset.zero & _viewport;
      if (!view.contains(screen.topLeft) ||
          !view.contains(screen.bottomRight)) {
        fitView();
      }
    });
  }

  void _clearTransient() {
    _sel = const _Selection.none();
    _drag = _DragMode.none;
    _connectingFrom = null;
    _dragEdgeIndex = null;
    _cursor = null;
  }

  void _flashWarn(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 2),
      ));
  }

  // ==============================================================
  //   WIDGETS
  // ==============================================================

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(context),
        const SizedBox(height: 8),
        Expanded(child: _buildCanvas(context)),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasSelection = _sel.type != _SelectionType.none;

    final viewButtons = <Widget>[
      IconButton(
        tooltip: 'Alejar',
        onPressed: () => _zoomBy(1 / 1.2),
        icon: const Icon(Icons.zoom_out),
      ),
      IconButton(
        tooltip: 'Acercar',
        onPressed: () => _zoomBy(1.2),
        icon: const Icon(Icons.zoom_in),
      ),
      TextButton.icon(
        onPressed: fitView,
        icon: const Icon(Icons.fit_screen),
        label: const Text('Ver todo'),
      ),
    ];

    if (widget.readOnly) {
      return Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: viewButtons,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<EditorTool>(
              segments: const [
                ButtonSegment(
                  value: EditorTool.select,
                  icon: Icon(Icons.near_me_outlined),
                  label: Text('Seleccionar'),
                ),
                ButtonSegment(
                  value: EditorTool.connect,
                  icon: Icon(Icons.trending_flat),
                  label: Text('Conectar'),
                ),
              ],
              selected: {_tool},
              onSelectionChanged: (s) => _setTool(s.first),
            ),
            OutlinedButton.icon(
              onPressed: hasSelection ? _deleteSelection : null,
              icon: Icon(Icons.delete_outline,
                  color: hasSelection ? colorScheme.error : null),
              label: const Text('Eliminar'),
            ),
            OutlinedButton.icon(
              onPressed: _nodes.isEmpty ? null : autoLayout,
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Ordenar'),
            ),
            ...viewButtons,
          ],
        ),
        if (_tool == EditorTool.connect)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _connectingFrom == null
                  ? 'Haz clic en la estación de origen.'
                  : 'Ahora haz clic en la estación de destino (Esc cancela).',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _buildCanvas(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.delete): _DeleteIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): _DeleteIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _CancelIntent(),
      },
      child: Actions(
        actions: {
          _DeleteIntent: CallbackAction<_DeleteIntent>(
              onInvoke: (_) => _deleteSelection()),
          _CancelIntent: CallbackAction<_CancelIntent>(
              onInvoke: (_) => setState(() {
                    _connectingFrom = null;
                    _cursor = null;
                  })),
        },
        child: Focus(
          focusNode: _focusNode,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: LayoutBuilder(builder: (context, constraints) {
                _viewport = constraints.biggest;
                return Listener(
                  onPointerSignal: _onPointerSignal,
                  child: MouseRegion(
                    cursor: _tool == EditorTool.connect && !widget.readOnly
                        ? SystemMouseCursors.precise
                        : MouseCursor.defer,
                    onHover: (e) => _onHover(e.localPosition),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _onTapDown(d.localPosition),
                      onPanStart: (d) => _onPanStart(d.localPosition),
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: (_) => _onPanEnd(),
                      child: CustomPaint(
                        size: constraints.biggest,
                        painter: _GraphPainter(
                          nodes: Map.of(_nodes),
                          pos: Map.of(_pos),
                          nodeSize: _nodeSize,
                          arrows: List.of(_arrows),
                          bends: Map.of(_bends),
                          selection: _sel,
                          connectingFrom: _connectingFrom,
                          cursor: _cursor,
                          draggingEdgeIndex: _dragEdgeIndex,
                          draggingSource: _drag == _DragMode.handleSource,
                          scale: _scale,
                          pan: _pan,
                          gridColor: colorScheme.outlineVariant,
                          nodeColor: colorScheme.surfaceContainerHighest,
                          selectedColor: colorScheme.primary,
                          textColor: colorScheme.onSurface,
                          mutedTextColor: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// Edge point of [rect] on the segment from its centre [from] toward [toward].
Offset _edgePoint(Offset from, Offset toward, Rect rect) {
  final d = toward - from;
  if (d.distance < 1e-6) return from;
  final halfW = rect.width / 2, halfH = rect.height / 2;
  final tx = d.dx.abs() < 1e-9 ? double.infinity : halfW / d.dx.abs();
  final ty = d.dy.abs() < 1e-9 ? double.infinity : halfH / d.dy.abs();
  final t = math.min(math.min(tx, ty), 1.0);
  return from + d * t;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// The points an arrow is drawn through: the edge of its source node, its
/// waypoints (if any), and the edge of its target node.
List<Offset> _arrowPoints(RouteArrow a, Map<int, Offset> pos,
    Map<RouteArrow, List<Offset>> bends, Size nodeSize) {
  final ra = pos[a.from]! & nodeSize, rb = pos[a.to]! & nodeSize;
  final via = bends[a] ?? const <Offset>[];
  final firstToward = via.isEmpty ? rb.center : via.first;
  final lastFrom = via.isEmpty ? ra.center : via.last;
  return [
    _edgePoint(ra.center, firstToward, ra),
    ...via,
    _edgePoint(rb.center, lastFrom, rb),
  ];
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.pos,
    required this.nodeSize,
    required this.arrows,
    required this.bends,
    required this.selection,
    required this.connectingFrom,
    required this.cursor,
    required this.draggingEdgeIndex,
    required this.draggingSource,
    required this.scale,
    required this.pan,
    required this.gridColor,
    required this.nodeColor,
    required this.selectedColor,
    required this.textColor,
    required this.mutedTextColor,
  });

  final Map<int, RouteNode> nodes;
  final Map<int, Offset> pos;
  final Size nodeSize;
  final List<RouteArrow> arrows;
  final Map<RouteArrow, List<Offset>> bends;
  final _Selection selection;
  final int? connectingFrom;
  final Offset? cursor;
  final int? draggingEdgeIndex;
  final bool draggingSource;
  final double scale;
  final Offset pan;
  final Color gridColor;
  final Color nodeColor;
  final Color selectedColor;
  final Color textColor;
  final Color mutedTextColor;

  Rect _rect(int key) => pos[key]! & nodeSize;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);

    // (1) Grilla sobre el área visible.
    final visible = Rect.fromLTWH(
        -pan.dx / scale, -pan.dy / scale, size.width / scale, size.height / scale);
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.35)
      ..strokeWidth = 1 / scale;
    const step = 32.0;
    for (double x = (visible.left / step).floor() * step;
        x < visible.right;
        x += step) {
      canvas.drawLine(Offset(x, visible.top), Offset(x, visible.bottom), grid);
    }
    for (double y = (visible.top / step).floor() * step;
        y < visible.bottom;
        y += step) {
      canvas.drawLine(Offset(visible.left, y), Offset(visible.right, y), grid);
    }

    // (2) Flechas: recta, o por sus puntos intermedios si "Ordenar" se los
    // dio (flechas que saltan columnas).
    for (var i = 0; i < arrows.length; i++) {
      final a = arrows[i];
      if (!pos.containsKey(a.from) || !pos.containsKey(a.to)) continue;
      final pts = _arrowPoints(a, pos, bends, nodeSize);
      if (i == draggingEdgeIndex && cursor != null) {
        final ra = _rect(a.from), rb = _rect(a.to);
        draggingSource
            ? _arrow(canvas, cursor!, _edgePoint(rb.center, cursor!, rb),
                dashed: true)
            : _arrow(canvas, _edgePoint(ra.center, cursor!, ra), cursor!,
                dashed: true);
        continue;
      }
      final selected =
          selection.type == _SelectionType.edge && selection.edgeIndex == i;
      final line = Paint()
        ..color = selected ? selectedColor : textColor
        ..strokeWidth = (selected ? 2.5 : 1.6) / scale
        ..style = PaintingStyle.stroke;
      for (var j = 0; j + 2 < pts.length; j++) {
        canvas.drawLine(pts[j], pts[j + 1], line);
      }
      _arrow(canvas, pts[pts.length - 2], pts.last, selected: selected);
      if (selected) {
        final h = Paint()..color = selectedColor;
        canvas.drawCircle(pts.first, 6 / scale, h);
        canvas.drawCircle(pts.last, 6 / scale, h);
      }
    }

    // (3) Flecha guía al conectar.
    if (connectingFrom != null &&
        cursor != null &&
        pos.containsKey(connectingFrom)) {
      final r = _rect(connectingFrom!);
      _arrow(canvas, _edgePoint(r.center, cursor!, r), cursor!, dashed: true);
    }

    // (4) Nodos: nombre de la estación.
    for (final key in pos.keys) {
      final node = nodes[key];
      if (node == null) continue;
      final rect = _rect(key);
      final isSel =
          selection.type == _SelectionType.node && selection.nodeKey == key;
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      canvas.drawRRect(
          rr,
          Paint()
            ..color =
                isSel ? selectedColor.withValues(alpha: 0.15) : nodeColor);
      canvas.drawRRect(
          rr,
          Paint()
            ..color = isSel ? selectedColor : mutedTextColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = (isSel ? 2.4 : 1.2) / scale);

      final title = TextPainter(
        text: TextSpan(
          text: node.machineName.isEmpty
              ? 'Estación ${node.machineTypeId}'
              : node.machineName,
          style: TextStyle(
              color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: nodeSize.width - 16);
      title.paint(
          canvas,
          Offset(rect.left + 8,
              rect.top + (rect.height - title.height) / 2));
    }

    canvas.restore();
  }

  void _arrow(Canvas canvas, Offset from, Offset to,
      {bool dashed = false, bool selected = false}) {
    final color = selected ? selectedColor : textColor;
    final paint = Paint()
      ..color = color
      ..strokeWidth = (selected ? 2.5 : 1.6) / scale
      ..style = PaintingStyle.stroke;
    final v = to - from;
    final len = v.distance;
    if (len < 1e-6) return;
    final u = v / len;
    if (!dashed) {
      canvas.drawLine(from, to, paint);
    } else {
      const dash = 8.0, gap = 6.0;
      for (double t = 0; t < len; t += dash + gap) {
        canvas.drawLine(from + u * t, from + u * math.min(t + dash, len), paint);
      }
    }
    const arrowLen = 12.0, arrowWidth = 5.5;
    final left = to - u * arrowLen + Offset(-u.dy, u.dx) * arrowWidth;
    final right = to - u * arrowLen + Offset(u.dy, -u.dx) * arrowWidth;
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}
