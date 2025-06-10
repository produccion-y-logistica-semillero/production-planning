import 'package:flutter/material.dart';
import 'dart:math';
import 'package:production_planning/entities/machine_type_entity.dart';

class NodeEditor extends StatefulWidget {
  final List<MachineTypeEntity> machines;
  final bool onlyGraph; // NUEVO

  const NodeEditor({super.key, required this.machines, this.onlyGraph = false});

  @override
  NodeEditorState createState() => NodeEditorState();
}

enum ToolMode { addConnection, deleteNode, deleteConnection }

class NodeEditorState extends State<NodeEditor> {
  final Map<int, Offset> nodePositions = {};
  final Map<int, MachineTypeEntity> nodeMachines = {};
  final List<Connection> connections = [];

  int? connectingFrom;
  Offset? cursorPosition;
  ToolMode currentMode = ToolMode.addConnection;

  void loadNodesAndConnections(List<MachineTypeEntity> machines, List<Connection> connectionsList) {
    setState(() {
      nodePositions.clear();
      nodeMachines.clear();
      connections.clear();
      double x = 100;
      double y = 100;
      for (final machine in machines) {
        nodePositions[machine.id!] = Offset(x, y);
        nodeMachines[machine.id!] = machine;
        x += 120;
        if (x > 600) {
          x = 100;
          y += 120;
        }
      }
      connections.addAll(connectionsList);
    });
  }

  void addNodeForMachine(MachineTypeEntity machine) {
    if (nodePositions.containsKey(machine.id)) return;
    setState(() {
      nodePositions[machine.id!] = const Offset(100, 100);
      nodeMachines[machine.id!] = machine;
    });
  }

  void removeNode(int id) {
    if (!nodePositions.containsKey(id)) return;
    setState(() {
      nodePositions.remove(id);
      nodeMachines.remove(id);
      connections.removeWhere((c) => c.source == id || c.target == id);
    });
  }

  void completeConnection(int to) {
    if (connectingFrom != null &&
        connectingFrom != to &&
        nodePositions.containsKey(connectingFrom) &&
        nodePositions.containsKey(to)) {
      final exists = connections.any((c) => c.source == connectingFrom && c.target == to);
      if (!exists) {
        setState(() {
          connections.add(Connection(connectingFrom!, to));
          connectingFrom = null;
          cursorPosition = null;
        });
      } else {
        setState(() {
          connectingFrom = null;
          cursorPosition = null;
        });
      }
    }
  }

  void startConnectingFrom(int id) {
    setState(() {
      connectingFrom = id;
    });
  }

  void cancelConnection() {
    setState(() {
      connectingFrom = null;
      cursorPosition = null;
    });
  }

  void removeConnection(Connection conn) {
    setState(() {
      connections.remove(conn);
    });
  }

  Connection? findConnectionAtOffset(Offset pos) {
    for (final conn in connections) {
      final p1 = nodePositions[conn.source]! + const Offset(40, 20);
      final p2 = nodePositions[conn.target]! + const Offset(40, 20);
      final distance = _distanceToSegment(pos, p1, p2);
      if (distance < 20) {
        return conn;
      }
    }
    return null;
  }

  double _distanceToSegment(Offset p, Offset v, Offset w) {
    final l2 = (v - w).distanceSquared;
    if (l2 == 0.0) return (p - v).distance;
    final t = max(0, min(1, ((p - v).dx * (w - v).dx + (p - v).dy * (w - v).dy) / l2));
    final projection = Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy));
    return (p - projection).distance;
  }

  int? findNodeAtOffset(Offset pos) {
    for (final entry in nodePositions.entries) {
      final rect = Rect.fromLTWH(entry.value.dx, entry.value.dy, 80, 52);
      if (rect.contains(pos)) {
        return entry.key;
      }
    }
    return null;
  }

  List<MachineTypeEntity> getNodes() {
    return nodeMachines.values.toList();
  }

  List<Connection> getConnections() {
    return List<Connection>.from(connections);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  GestureDetector(
                    onPanUpdate: (details) {
                      if (connectingFrom != null && currentMode == ToolMode.addConnection) {
                        setState(() {
                          cursorPosition = details.localPosition;
                        });
                      }
                    },
                    onTapDown: (details) {
                      if (currentMode == ToolMode.deleteConnection) {
                        final conn = findConnectionAtOffset(details.localPosition);
                        if (conn != null) removeConnection(conn);
                      } else if (currentMode == ToolMode.deleteNode) {
                        final nodeId = findNodeAtOffset(details.localPosition);
                        if (nodeId != null) removeNode(nodeId);
                      } else if (currentMode == ToolMode.addConnection && connectingFrom != null) {
                        cancelConnection();
                      }
                    },
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size.infinite,
                          painter: ConnectionPainter(
                            nodePositions,
                            connections,
                            connectingFrom,
                            cursorPosition,
                            currentMode == ToolMode.deleteConnection,
                          ),
                        ),
                        ...nodePositions.entries.map(
                          (entry) => DraggableNode(
                            id: entry.key,
                            offset: entry.value,
                            tipo: nodeMachines[entry.key]?.name ?? '',
                            isConnectingFrom: connectingFrom == entry.key,
                            onDrag: (newOffset) {
                              setState(() {
                                final double minX = 0;
                                final double minY = 0;
                                final double maxX = constraints.maxWidth - 80;
                                final double maxY = constraints.maxHeight - 52;
                                final Offset limited = Offset(
                                  newOffset.dx.clamp(minX, maxX),
                                  newOffset.dy.clamp(minY, maxY),
                                );
                                nodePositions[entry.key] = limited;
                              });
                            },
                            onDelete: () {
                              if (currentMode == ToolMode.deleteNode) removeNode(entry.key);
                            },
                            onDoubleTap: () {
                              if (currentMode == ToolMode.addConnection) {
                                if (connectingFrom == null) {
                                  startConnectingFrom(entry.key);
                                } else {
                                  completeConnection(entry.key);
                                }
                              }
                            },
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (!widget.onlyGraph)
          BottomAppBar(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_link),
                  onPressed: () => setState(() => currentMode = ToolMode.addConnection),
                  color: currentMode == ToolMode.addConnection ? Colors.blue : null,
                ),
                IconButton(
                  icon: const Icon(Icons.indeterminate_check_box),
                  onPressed: () => setState(() => currentMode = ToolMode.deleteNode),
                  color: currentMode == ToolMode.deleteNode ? Colors.red : null,
                ),
                IconButton(
                  icon: const Icon(Icons.link_off),
                  onPressed: () => setState(() => currentMode = ToolMode.deleteConnection),
                  color: currentMode == ToolMode.deleteConnection ? Colors.red : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class DraggableNode extends StatefulWidget {
  final int id;
  final Offset offset;
  final String tipo;
  final bool isConnectingFrom;
  final void Function(Offset) onDrag;
  final VoidCallback onDelete;
  final VoidCallback onDoubleTap;

  const DraggableNode({
    super.key,
    required this.id,
    required this.offset,
    required this.tipo,
    required this.onDrag,
    required this.onDelete,
    required this.onDoubleTap,
    required this.isConnectingFrom,
  });

  @override
  State<DraggableNode> createState() => _DraggableNodeState();
}

class _DraggableNodeState extends State<DraggableNode> {
  late Offset position;

  @override
  void initState() {
    super.initState();
    position = widget.offset;
  }

  @override
  void didUpdateWidget(covariant DraggableNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.offset != oldWidget.offset) {
      position = widget.offset;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onLongPress: widget.onDelete,
        onDoubleTap: widget.onDoubleTap,
        onPanUpdate: (details) {
          setState(() {
            position += details.delta;
            widget.onDrag(position);
          });
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isConnectingFrom ? Colors.orange : Colors.deepPurple,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${widget.tipo}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class Connection {
  final int source;
  final int target;

  Connection(this.source, this.target);
}

class ConnectionPainter extends CustomPainter {
  final Map<int, Offset> positions;
  final List<Connection> connections;
  final int? connectingFrom;
  final Offset? cursorPosition;
  final bool showTrashIcon;

  ConnectionPainter(
    this.positions,
    this.connections,
    this.connectingFrom,
    this.cursorPosition,
    this.showTrashIcon,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2;

    for (final conn in connections) {
      final start = positions[conn.source];
      final end = positions[conn.target];
      if (start != null && end != null) {
        final p1 = start + const Offset(40, 20);
        final p2 = end + const Offset(40, 20);
        _drawArrow(canvas, p1, p2, paint);

        if (showTrashIcon) {
          final middle = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
          final iconPainter = TextPainter(
            text: const TextSpan(
              text: '🗑️',
              style: TextStyle(fontSize: 20),
            ),
            textDirection: TextDirection.ltr,
          );
          iconPainter.layout();
          iconPainter.paint(canvas, middle - Offset(iconPainter.width / 2, iconPainter.height / 2));
        }
      }
    }

    if (connectingFrom != null && cursorPosition != null && positions.containsKey(connectingFrom)) {
      final start = positions[connectingFrom]! + const Offset(40, 20);
      final end = cursorPosition!;
      _drawArrow(canvas, start, end, paint);
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    const double nodeRadius = 40;
    final double arrowSize = 16;
    final double angle = atan2(end.dy - start.dy, end.dx - start.dx);

    final adjustedEnd = Offset(
      end.dx - nodeRadius * cos(angle),
      end.dy - nodeRadius * sin(angle),
    );

    canvas.drawLine(start, adjustedEnd, paint);

    final arrowAngle = pi / 7;
    final p1 = Offset(
      adjustedEnd.dx - arrowSize * cos(angle - arrowAngle),
      adjustedEnd.dy - arrowSize * sin(angle - arrowAngle),
    );
    final p2 = Offset(
      adjustedEnd.dx - arrowSize * cos(angle + arrowAngle),
      adjustedEnd.dy - arrowSize * sin(angle + arrowAngle),
    );
    canvas.drawLine(adjustedEnd, p1, paint);
    canvas.drawLine(adjustedEnd, p2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}