import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/services/scheduling/machine_plan_text.dart';
import 'package:production_planning/services/scheduling/machine_sequence_plan.dart';

/// Dialogo para definir la secuencia POR MAQUINA y, donde la ruta es parte de
/// la solucion (Open Shop), la ruta de cada job. Son las dos tablas de la
/// hoja de referencia:
///
///   Ruta [DECISION]       Job x Op      -> maquina que visita en cada operacion
///   Secuencia [DECISION]  Maquina x Pos -> job que procesa en cada posicion
///
/// La secuencia es estricta: cada maquina procesa sus jobs exactamente en
/// ese orden. Antes de aceptar se valida con el mismo codigo que programa
/// (conteos, rutas, interbloqueo). Devuelve un [MachinePlan]; null si cancela.
class MachineSequenceDialog extends StatefulWidget {
  final List<JobEntity> jobs;

  /// Maquinas de cada estacion (machineTypeId -> maquinas).
  final Map<int, List<MachineEntity>> machinesByType;

  /// Nombre de cada estacion (machineTypeId -> nombre).
  final Map<int, String> stationNames;

  /// Si la ruta es parte de la solucion (Open Shop): muestra la tabla de ruta.
  final bool freeRoute;

  /// Plan previo para seguir editandolo.
  final MachinePlan? initial;

  const MachineSequenceDialog({
    super.key,
    required this.jobs,
    required this.machinesByType,
    required this.stationNames,
    required this.freeRoute,
    this.initial,
  });

  @override
  State<MachineSequenceDialog> createState() => _MachineSequenceDialogState();
}

class _MachineSequenceDialogState extends State<MachineSequenceDialog> {
  late final List<JobEntity> _jobs;
  late final List<MachineEntity> _machines;
  late final List<SeqOperation> _ops;

  /// machineId -> jobId (or null = empty) per position.
  final Map<int, List<int?>> _seq = {};

  /// jobId -> machineId (or null) per operation.
  final Map<int, List<int?>> _route = {};

  String? _error;
  List<String> _involved = const [];

  @override
  void initState() {
    super.initState();
    _jobs = widget.jobs.where((j) => j.jobId != null).toList();
    _machines = [
      for (final e in widget.machinesByType.entries) ...e.value,
    ]..sort((a, b) => a.id!.compareTo(b.id!));
    _ops = seqOperationsFromJobs(
      _jobs,
      widget.machinesByType,
      chainWhenNoDependencies: !widget.freeRoute,
    );
    for (final m in _machines) {
      _seq[m.id!] = List<int?>.filled(_capacity(m.id!), null);
    }
    for (final j in _jobs) {
      _route[j.jobId!] = List<int?>.filled(_opsOf(j.jobId!).length, null);
    }
    final initial = widget.initial;
    if (initial != null) {
      initial.machineSequences.forEach((m, jobs) {
        final row = _seq[m];
        if (row == null) return;
        for (int i = 0; i < jobs.length && i < row.length; i++) {
          row[i] = jobs[i];
        }
      });
      initial.routes?.forEach((j, machines) {
        final row = _route[j];
        if (row == null) return;
        for (int i = 0; i < machines.length && i < row.length; i++) {
          row[i] = machines[i];
        }
      });
    }
  }

  List<SeqOperation> _opsOf(int jobId) =>
      _ops.where((o) => o.jobId == jobId).toList();

  /// How many operations can run on the machine = its positions.
  int _capacity(int machineId) =>
      _ops.where((o) => o.machines.contains(machineId)).length;

  String _jobLabel(int id) {
    final j = _jobs.where((j) => j.jobId == id);
    return j.isEmpty ? '#$id' : (j.first.jobName ?? 'Trabajo $id');
  }

  String _machineLabel(int id) {
    final m = _machines.where((m) => m.id == id);
    return m.isEmpty ? '#$id' : m.first.name;
  }

  String _stationOf(MachineEntity m) =>
      widget.stationNames[m.machineTypeId] ?? '';

  /// Jobs with at least one operation that can run on the machine.
  List<int> _jobsFor(int machineId) => [
        for (final j in _jobs)
          if (_ops.any(
              (o) => o.jobId == j.jobId && o.machines.contains(machineId)))
            j.jobId!,
      ];

  /// Machines any operation of the job can run on.
  List<int> _machinesFor(int jobId) => [
        for (final m in _machines)
          if (_opsOf(jobId).any((o) => o.machines.contains(m.id))) m.id!,
      ];

  void _clear() => setState(() {
        for (final row in _seq.values) {
          row.fillRange(0, row.length, null);
        }
        for (final row in _route.values) {
          row.fillRange(0, row.length, null);
        }
        _error = null;
        _involved = const [];
      });

  /// Same order on every machine (a permutation): never deadlocks. A
  /// starting point to edit, not a final answer.
  void _prefill(int Function(JobEntity a, JobEntity b) compare) {
    final order = [..._jobs]..sort((a, b) {
        final c = compare(a, b);
        return c != 0 ? c : a.jobId!.compareTo(b.jobId!);
      });
    final lists = {for (final m in _machines) m.id!: <int>[]};
    final routes = {for (final j in _jobs) j.jobId!: <int>[]};
    for (final job in order) {
      for (final op in _opsOf(job.jobId!)) {
        final options = op.machines.toList()
          ..sort((a, b) {
            final c = lists[a]!.length.compareTo(lists[b]!.length);
            return c != 0 ? c : a.compareTo(b);
          });
        if (options.isEmpty) continue;
        lists[options.first]!.add(job.jobId!);
        routes[job.jobId!]!.add(options.first);
      }
    }
    setState(() {
      lists.forEach((m, jobs) {
        final row = _seq[m]!;
        row.fillRange(0, row.length, null);
        for (int i = 0; i < jobs.length && i < row.length; i++) {
          row[i] = jobs[i];
        }
      });
      if (widget.freeRoute) {
        routes.forEach((j, machines) {
          final row = _route[j]!;
          row.fillRange(0, row.length, null);
          for (int i = 0; i < machines.length && i < row.length; i++) {
            row[i] = machines[i];
          }
        });
      }
      _error = null;
      _involved = const [];
    });
  }

  /// The tables as a plan, or null (with [_error] set) if they are wrong.
  MachinePlan? _collect() {
    final sequences = <int, List<int>>{};
    for (final entry in _seq.entries) {
      final row = entry.value;
      final firstEmpty = row.indexOf(null);
      if (firstEmpty != -1 && row.skip(firstEmpty).any((v) => v != null)) {
        _fail('La secuencia de ${_machineLabel(entry.key)} tiene huecos: '
            'llene las posiciones en orden, sin dejar vacías en medio.');
        return null;
      }
      final jobs = [
        for (final v in row)
          if (v != null) v,
      ];
      if (jobs.isNotEmpty) sequences[entry.key] = jobs;
    }
    if (sequences.isEmpty) {
      _fail('Defina la secuencia de al menos una máquina.');
      return null;
    }

    Map<int, List<int>>? routes;
    if (widget.freeRoute) {
      routes = {};
      for (final entry in _route.entries) {
        final row = entry.value;
        if (row.every((v) => v == null)) continue; // free: queues decide
        if (row.contains(null)) {
          _fail('La ruta de ${_jobLabel(entry.key)} está incompleta: '
              'escriba la máquina de cada operación o deje toda la fila '
              'vacía.');
          return null;
        }
        routes[entry.key] = [for (final v in row) v!];
      }
      if (routes.isEmpty) routes = null;
    }

    final plan = MachinePlan(machineSequences: sequences, routes: routes);
    try {
      buildMachineSequencePlan(
        ops: _ops,
        machineSequences: sequences,
        userRoutes: routes,
      );
    } on MachineSequenceException catch (e) {
      _fail(
        e.message,
        [
          for (final (job, task) in e.involved)
            '${_jobLabel(job)} (${_taskName(job, task)})',
        ],
      );
      return null;
    }
    return plan;
  }

  String _taskName(int jobId, int taskId) {
    for (final j in _jobs) {
      if (j.jobId != jobId) continue;
      for (final t in j.sequence?.tasks ?? const []) {
        if (t.id == taskId) {
          return widget.stationNames[t.machineTypeId] ?? 'operación';
        }
      }
    }
    return 'operación';
  }

  void _fail(String message, [List<String> involved = const []]) {
    setState(() {
      _error = message;
      _involved = involved;
    });
  }

  void _validate() {
    final plan = _collect();
    if (plan != null) {
      setState(() {
        _error = null;
        _involved = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Plan válido: se puede programar sin interbloqueo.'),
      ));
    }
  }

  void _accept() {
    final plan = _collect();
    if (plan != null) Navigator.of(context).pop(plan);
  }

  Future<void> _paste() async {
    String initialText = '';
    try {
      initialText = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } catch (_) {}
    if (!mounted) return;
    final controller = TextEditingController(text: initialText);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pegar desde Excel'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copie las celdas de las tablas y péguelas aquí. Se leen la '
                'tabla que empieza con "Job" (ruta: Op 1, Op 2…) y la que '
                'empieza con "Máquina" (secuencia: Pos 1, Pos 2…), con los '
                'mismos nombres de jobs y máquinas del programa.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Job\tOp 1\tOp 2\nJ1\tM1\tM2\n…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    _applyPasted(text);
  }

  String _key(String s) => s.trim().toLowerCase();

  void _applyPasted(String text) {
    final pasted = parsePastedMachinePlan(text);
    if (pasted.isEmpty) {
      _fail('No encontré tablas: la de ruta empieza con "Job" y la de '
          'secuencia con "Máquina".');
      return;
    }
    final jobByName = {
      for (final j in _jobs) _key(j.jobName ?? 'Trabajo ${j.jobId}'): j.jobId!,
    };
    final machineByName = {for (final m in _machines) _key(m.name): m.id!};

    final newSeq = <int, List<int>>{};
    for (final e in pasted.sequences.entries) {
      final machine = machineByName[_key(e.key)];
      if (machine == null) {
        _fail('La máquina "${e.key}" del texto pegado no existe en el '
            'programa.');
        return;
      }
      final jobs = <int>[];
      for (final name in e.value) {
        final job = jobByName[_key(name)];
        if (job == null) {
          _fail('El job "$name" (máquina ${e.key}) no existe en el programa.');
          return;
        }
        jobs.add(job);
      }
      if (jobs.length > _seq[machine]!.length) {
        _fail('La máquina ${e.key} tiene ${jobs.length} posiciones pero solo '
            'caben ${_seq[machine]!.length}.');
        return;
      }
      newSeq[machine] = jobs;
    }

    final newRoute = <int, List<int>>{};
    if (widget.freeRoute) {
      for (final e in pasted.routes.entries) {
        final job = jobByName[_key(e.key)];
        if (job == null) {
          _fail('El job "${e.key}" de la tabla de ruta no existe en el '
              'programa.');
          return;
        }
        final machines = <int>[];
        for (final name in e.value) {
          final machine = machineByName[_key(name)];
          if (machine == null) {
            _fail('La máquina "$name" (ruta de ${e.key}) no existe en el '
                'programa.');
            return;
          }
          machines.add(machine);
        }
        if (machines.length > _route[job]!.length) {
          _fail('La ruta de ${e.key} tiene ${machines.length} operaciones '
              'pero el job solo tiene ${_route[job]!.length}.');
          return;
        }
        newRoute[job] = machines;
      }
    }

    setState(() {
      newSeq.forEach((m, jobs) {
        final row = _seq[m]!;
        row.fillRange(0, row.length, null);
        for (int i = 0; i < jobs.length; i++) {
          row[i] = jobs[i];
        }
      });
      newRoute.forEach((j, machines) {
        final row = _route[j]!;
        row.fillRange(0, row.length, null);
        for (int i = 0; i < machines.length; i++) {
          row[i] = machines[i];
        }
      });
      _error = null;
      _involved = const [];
    });
  }

  Widget _dropdown(
      int? value, List<(int, String)> options, ValueChanged<int?> onChanged) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int?>(
        value: options.any((o) => o.$1 == value) ? value : null,
        isDense: true,
        isExpanded: true,
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('—')),
          for (final o in options)
            DropdownMenuItem<int?>(value: o.$1, child: Text(o.$2)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _rowLabel(String title, [String? subtitle]) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (subtitle != null && subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(fontSize: 11)),
          ],
        ),
      );

  Widget _section(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(subtitle,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );

  Widget _routeTable() {
    final cols =
        _route.values.fold<int>(0, (a, r) => r.length > a ? r.length : a);
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: outline),
        defaultColumnWidth: const FixedColumnWidth(104),
        columnWidths: const {0: FixedColumnWidth(130)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            _headerCell('Job'),
            for (int k = 0; k < cols; k++) _headerCell('Op ${k + 1}'),
          ]),
          for (final job in _jobs)
            TableRow(children: [
              _rowLabel(_jobLabel(job.jobId!)),
              for (int k = 0; k < cols; k++)
                k < _route[job.jobId!]!.length
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _dropdown(
                          _route[job.jobId!]![k],
                          [
                            for (final m in _machinesFor(job.jobId!))
                              (m, _machineLabel(m)),
                          ],
                          (v) => setState(() => _route[job.jobId!]![k] = v),
                        ),
                      )
                    : const SizedBox.shrink(),
            ]),
        ],
      ),
    );
  }

  Widget _sequenceTable() {
    final cols =
        _seq.values.fold<int>(0, (a, r) => r.length > a ? r.length : a);
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: outline),
        defaultColumnWidth: const FixedColumnWidth(104),
        columnWidths: const {0: FixedColumnWidth(130)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            _headerCell('Máquina'),
            for (int k = 0; k < cols; k++) _headerCell('Pos ${k + 1}'),
          ]),
          for (final m in _machines)
            TableRow(children: [
              _rowLabel(m.name, _stationOf(m)),
              for (int k = 0; k < cols; k++)
                k < _seq[m.id!]!.length
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _dropdown(
                          _seq[m.id!]![k],
                          [
                            for (final j in _jobsFor(m.id!)) (j, _jobLabel(j)),
                          ],
                          (v) => setState(() => _seq[m.id!]![k] = v),
                        ),
                      )
                    : const SizedBox.shrink(),
            ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Secuencia por máquina'),
      content: SizedBox(
        width: 760,
        height: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Escriba el orden en que cada máquina procesa los jobs. Es '
                'estricto: la máquina espera al siguiente de su lista aunque '
                'quede ociosa. Un job aparece una vez por cada operación que '
                'tiene en esa máquina (puede repetir máquina).',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Partir de:',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ActionChip(
                    label: const Text('FIFO (llegada)'),
                    onPressed: () => _prefill(
                        (a, b) => a.availableDate.compareTo(b.availableDate)),
                  ),
                  ActionChip(
                    label: const Text('EDD (entrega)'),
                    onPressed: () =>
                        _prefill((a, b) => a.dueDate.compareTo(b.dueDate)),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.content_paste, size: 16),
                    label: const Text('Pegar desde Excel'),
                    onPressed: _paste,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Limpiar'),
                    onPressed: _clear,
                  ),
                ],
              ),
              if (widget.freeRoute) ...[
                _section(
                  'Ruta [DECISIÓN]',
                  'Elija la máquina que visita cada job en cada operación. '
                      'Se permite repetir máquina. Deje la fila vacía para '
                      'que el orden salga de las secuencias de máquina.',
                ),
                _routeTable(),
              ],
              _section(
                'Secuencia por máquina [DECISIÓN]',
                'Elija el job de cada posición, en orden y sin huecos.',
              ),
              _sequenceTable(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_error!,
                          style:
                              TextStyle(color: colorScheme.onErrorContainer)),
                      if (_involved.isNotEmpty)
                        Text('Operaciones implicadas: ${_involved.join(', ')}',
                            style: TextStyle(
                                color: colorScheme.onErrorContainer,
                                fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(onPressed: _validate, child: const Text('Validar')),
        FilledButton(onPressed: _accept, child: const Text('Aceptar')),
      ],
    );
  }
}
