import 'package:flutter/material.dart';
import 'graph_editor.dart';
import 'package:production_planning/entities/machine_type_entity.dart';

class SequenceEditorPanel extends StatelessWidget {
  final TextEditingController nameController;
  final VoidCallback onSave;
  final List<MachineTypeEntity> machines;
  final GlobalKey<NodeEditorState> nodeEditorKey;

  const SequenceEditorPanel({
    super.key,
    required this.nameController,
    required this.onSave,
    required this.machines,
    required this.nodeEditorKey,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: 'Nombre de la secuencia',
              labelStyle: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save),
              label: const Text('Guardar Trabajo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            fit: FlexFit.loose,
            child: NodeEditor(key: nodeEditorKey, machines: machines),
          ),
        ],
      ),
    );
  }
}