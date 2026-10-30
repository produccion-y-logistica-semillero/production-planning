import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:production_planning/entities/job_entity.dart';

/// Dialogo para que el usuario defina su propia secuencia de trabajos, como
/// alternativa a las reglas. Se arrastra cada trabajo a su posicion (o se
/// parte de un orden clasico) y se devuelve la lista de jobId en ese orden;
/// null si cancela.
class UserSequenceDialog extends StatefulWidget {
  final List<JobEntity> jobs;

  /// Secuencia previa (jobId) para seguir editandola.
  final List<int>? initial;

  const UserSequenceDialog({super.key, required this.jobs, this.initial});

  @override
  State<UserSequenceDialog> createState() => _UserSequenceDialogState();
}

class _UserSequenceDialogState extends State<UserSequenceDialog> {
  late List<JobEntity> _order;
  final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    final jobs = widget.jobs.where((j) => j.jobId != null).toList();
    final initial = widget.initial;
    if (initial == null) {
      _order = jobs;
    } else {
      final byId = {for (final j in jobs) j.jobId!: j};
      _order = [
        for (final id in initial)
          if (byId.containsKey(id)) byId.remove(id)!,
        ...byId.values,
      ];
    }
  }

  void _sortBy(int Function(JobEntity a, JobEntity b) compare) {
    setState(() => _order.sort((a, b) {
          final c = compare(a, b);
          return c != 0 ? c : a.jobId!.compareTo(b.jobId!);
        }));
  }

  String _name(JobEntity j) => j.jobName ?? 'Trabajo ${j.jobId}';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Secuencia del usuario'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Arrastre los trabajos (≡) al orden en que quiere programarlos. '
              'En Flow Shop es la permutación exacta; en los demás ambientes '
              'es la prioridad al despachar.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text('Partir de:',
                    style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ActionChip(
                  label: const Text('FIFO (llegada)'),
                  onPressed: () => _sortBy(
                      (a, b) => a.availableDate.compareTo(b.availableDate)),
                ),
                ActionChip(
                  label: const Text('EDD (entrega)'),
                  onPressed: () =>
                      _sortBy((a, b) => a.dueDate.compareTo(b.dueDate)),
                ),
                ActionChip(
                  label: const Text('Prioridad'),
                  onPressed: () =>
                      _sortBy((a, b) => b.priority.compareTo(a.priority)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TutorialTarget(
                id: 'useq.list',
                child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorder: (from, to) => setState(() {
                  if (to > from) to -= 1;
                  _order.insert(to, _order.removeAt(from));
                }),
                itemBuilder: (context, i) {
                  final job = _order[i];
                  return ListTile(
                    key: ValueKey(job.jobId),
                    leading: CircleAvatar(
                      radius: 14,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    title: Text(_name(job)),
                    subtitle: Text(
                      'Llega ${_fmt.format(job.availableDate)} · '
                      'Entrega ${_fmt.format(job.dueDate)} · '
                      'Prioridad ${job.priority}',
                    ),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                  );
                },
              ),
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
        TutorialTarget(
          id: 'useq.ok',
          child: FilledButton(
            onPressed: () =>
                Navigator.of(context).pop([for (final j in _order) j.jobId!]),
            child: const Text('Usar esta secuencia'),
          ),
        ),
      ],
    );
  }
}
