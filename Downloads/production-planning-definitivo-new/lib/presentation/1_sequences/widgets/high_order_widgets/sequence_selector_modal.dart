import 'package:flutter/material.dart';
import 'package:production_planning/entities/sequence_entity.dart';

class SequenceSelectorModal extends StatelessWidget {
  final List<SequenceEntity> sequences;
  final void Function(int id) onSelect;
  final void Function(int id) onDelete;

  const SequenceSelectorModal({
    super.key,
    required this.sequences,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      children: [
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Rutas de proceso',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        if (sequences.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No hay rutas registradas',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sequences.length,
            itemBuilder: (context, index) {
              final seq = sequences[index];
              return ListTile(
                title: Text(seq.name),
                leading: Icon(Icons.settings, color: colorScheme.primary),
                trailing: IconButton(
                  icon: Icon(Icons.delete, color: colorScheme.error),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('¿Eliminar ruta?'),
                        content: Text('¿Estás seguro de eliminar "${seq.name}"?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Eliminar'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      onDelete(seq.id!);
                    }
                  },
                ),
                onTap: () => onSelect(seq.id!),
              );
            },
          ),
        const SizedBox(height: 16),
      ],
    );
  }

}
