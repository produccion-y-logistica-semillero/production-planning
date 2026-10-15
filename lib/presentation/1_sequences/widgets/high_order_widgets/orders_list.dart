import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_state.dart';

/// Saved process routes, with a search box. Clicking one shows it.
class RouteListPanel extends StatefulWidget {
  final VoidCallback onNewRoute;

  const RouteListPanel({super.key, required this.onNewRoute});

  @override
  State<RouteListPanel> createState() => _RouteListPanelState();
}

class _RouteListPanelState extends State<RouteListPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<SeeProcessBloc, SeeProcessState>(
      builder: (context, state) {
        if (state is SeeProcessInitialState) {
          context.read<SeeProcessBloc>().retrieveSequences();
        }
        final q = _query.trim().toLowerCase();
        final routes = [
          for (final seq in state.sequences ?? const [])
            if (q.isEmpty || seq.name.toLowerCase().contains(q)) seq,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: widget.onNewRoute,
              icon: const Icon(Icons.add),
              label: const Text('Nueva ruta de proceso'),
            ),
            const SizedBox(height: 16),
            Text('Rutas de proceso',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar ruta',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: state.sequences == null
                  ? (state is SequencesRetrieveFailure
                      ? const Center(child: Text('No se pudieron cargar las rutas'))
                      : const Center(child: CircularProgressIndicator()))
                  : routes.isEmpty
                      ? Center(
                          child: Text(
                            (state.sequences ?? const []).isEmpty
                                ? 'No hay rutas registradas'
                                : 'Ninguna ruta coincide',
                            style:
                                TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          itemCount: routes.length,
                          itemBuilder: (context, i) {
                            final seq = routes[i];
                            final selected = seq.id == state.selectedProcess;
                            return ListTile(
                              dense: true,
                              selected: selected,
                              selectedTileColor:
                                  colorScheme.primaryContainer.withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              leading: const Icon(Icons.account_tree_outlined),
                              title: Text(seq.name),
                              onTap: () => context
                                  .read<SeeProcessBloc>()
                                  .selectSequence(seq.id!),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
