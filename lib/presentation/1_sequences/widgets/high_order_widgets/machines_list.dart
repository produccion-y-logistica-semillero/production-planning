import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_type_entity.dart';

/// Palette of stations (machine types) to add to the route, with a search
/// box. Clicking a station adds it to the canvas.
class MachinesList extends StatefulWidget {
  final List<MachineTypeEntity> machineTypes;
  final Function(MachineTypeEntity) onSelectMachine;

  const MachinesList({
    super.key,
    required this.machineTypes,
    required this.onSelectMachine,
  });

  @override
  State<MachinesList> createState() => _MachinesListState();
}

class _MachinesListState extends State<MachinesList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final shown = widget.machineTypes
        .where((m) =>
            q.isEmpty ||
            m.name.toLowerCase().contains(q) ||
            m.description.toLowerCase().contains(q))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Estaciones',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Haz clic en una estación para agregarla a la ruta.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Buscar estación',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text('Ninguna estación coincide',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)))
              : ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final m = shown[index];
                    return Material(
                      color: colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(m.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: m.description.isEmpty
                            ? null
                            : Text(m.description,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Icon(Icons.add_circle_outline,
                            color: colorScheme.primary),
                        onTap: () => widget.onSelectMachine(m),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
