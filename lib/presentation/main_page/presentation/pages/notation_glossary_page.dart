import 'package:flutter/material.dart';
import 'package:production_planning/shared/notation.dart';

/// Glossary of the theoretical notation (α | β | γ, data, objectives and
/// the formula of every rule), with a search box.
class NotationGlossaryPage extends StatefulWidget {
  const NotationGlossaryPage({super.key});

  @override
  State<NotationGlossaryPage> createState() => _NotationGlossaryPageState();
}

class _NotationGlossaryPageState extends State<NotationGlossaryPage> {
  String _query = '';

  bool _matches(NotationEntry e) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return e.symbol.toLowerCase().contains(q) ||
        e.name.toLowerCase().contains(q) ||
        e.definition.toLowerCase().contains(q) ||
        (e.formula?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Notación teórica',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Cómo se escribe en la literatura de programación de operaciones '
            'lo que la plataforma muestra con nombres sencillos.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool>(
            valueListenable: showNotation,
            builder: (context, on, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar la notación en todas las pantallas'),
              subtitle: const Text(
                  'También se activa desde "Notación teórica" en el menú.'),
              value: on,
              onChanged: (v) => setNotation(v),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar símbolo, nombre o fórmula (ej. Tj, Johnson)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 16),
          for (final section in NotationSection.values) ...[
            if (kNotation.any((e) => e.section == section && _matches(e))) ...[
              Text(section.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600)),
              const Divider(),
              for (final e in kNotation)
                if (e.section == section && _matches(e)) NotationTile(entry: e),
              const SizedBox(height: 16),
            ],
          ],
          Text('Fuente: $notationReference',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
