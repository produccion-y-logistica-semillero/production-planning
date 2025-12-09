import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/setup_time_entity.dart';
import 'package:production_planning/services/machines_service.dart';
import 'package:production_planning/services/sequences_service.dart';
import 'package:production_planning/services/setup_time_service.dart';

class SetupTimesPage extends StatefulWidget {
  const SetupTimesPage({super.key});

  @override
  State<SetupTimesPage> createState() => _SetupTimesPageState();
}

class _SetupTimesPageState extends State<SetupTimesPage> {
  final SetupTimeService _setupTimeService = depIn<SetupTimeService>();
  final MachinesService _machinesService = depIn<MachinesService>();
  final SequencesService _sequencesService = depIn<SequencesService>();

  List<MachineEntity> _machines = [];
  List<SequenceEntity> _sequences = [];
  List<SetupTimeEntity> _setupTimes = [];

  MachineEntity? _selectedMachine;
  SequenceEntity? _selectedFromSequence;
  SequenceEntity? _selectedToSequence;
  final TextEditingController _durationController = TextEditingController();

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    // Cargar tipos de máquina y máquinas
    final machineTypesResult = await _machinesService.getMachineTypes();
    final List<MachineEntity> allMachines = [];

    await machineTypesResult.fold(
      (_) async {},
      (types) async {
        for (final type in types) {
          final machinesResult = await _machinesService.getMachines(type.id!);
          machinesResult.fold(
            (_) {},
            (machines) => allMachines.addAll(machines),
          );
        }
      },
    );

    // Cargar secuencias
    final sequencesResult = await _sequencesService.getSequences();
    final sequences = sequencesResult.fold((_) => <SequenceEntity>[], (s) => s);

    setState(() {
      _machines = allMachines;
      _sequences = sequences;
      _loading = false;
    });

    if (_machines.isNotEmpty) {
      _selectedMachine = _machines.first;
      await _loadSetupTimes();
    }
  }

  Future<void> _loadSetupTimes() async {
    if (_selectedMachine == null) return;

    final result =
        await _setupTimeService.getSetupTimesByMachine(_selectedMachine!.id!);
    result.fold(
      (_) {},
      (setupTimes) {
        setState(() {
          _setupTimes = setupTimes;
        });
      },
    );
  }

  Future<void> _saveSetupTime() async {
    if (_selectedMachine == null || _selectedToSequence == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona máquina y secuencia destino')),
      );
      return;
    }

    final minutes = int.tryParse(_durationController.text);
    if (minutes == null || minutes < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una duración válida en minutos')),
      );
      return;
    }

    final result = await _setupTimeService.addSetupTime(
      machineId: _selectedMachine!.id!,
      fromSequenceId: _selectedFromSequence?.id,
      toSequenceId: _selectedToSequence!.id!,
      setupDuration: Duration(minutes: minutes),
    );

    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error al guardar tiempo de alistamiento')),
        );
      },
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tiempo de alistamiento guardado')),
        );
        _durationController.clear();
        _selectedFromSequence = null;
        _selectedToSequence = null;
        _loadSetupTimes();
      },
    );
  }

  Future<void> _deleteSetupTime(int id) async {
    final result = await _setupTimeService.deleteSetupTime(id);
    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error al eliminar tiempo de alistamiento')),
        );
      },
      (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tiempo de alistamiento eliminado')),
        );
        _loadSetupTimes();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_machines.isEmpty) {
      return const Center(
        child: Text('No hay máquinas disponibles. Crea máquinas primero.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tiempos de Alistamiento Dependientes de Secuencia',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configura los tiempos de cambio entre diferentes secuencias en cada máquina',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // Formulario de configuración
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nueva Configuración',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<MachineEntity>(
                    initialValue: _selectedMachine,
                    decoration: const InputDecoration(
                      labelText: 'Máquina',
                      border: OutlineInputBorder(),
                    ),
                    items: _machines.map((machine) {
                      return DropdownMenuItem(
                        value: machine,
                        child: Text(machine.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedMachine = value;
                      });
                      _loadSetupTimes();
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<SequenceEntity?>(
                    initialValue: _selectedFromSequence,
                    decoration: const InputDecoration(
                      labelText:
                          'Desde Secuencia (opcional - vacío = cualquiera)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<SequenceEntity?>(
                        value: null,
                        child: Text('-- Cualquier secuencia --'),
                      ),
                      ..._sequences.map((seq) {
                        return DropdownMenuItem<SequenceEntity?>(
                          value: seq,
                          child: Text(seq.name),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedFromSequence = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<SequenceEntity>(
                    initialValue: _selectedToSequence,
                    decoration: const InputDecoration(
                      labelText: 'Hacia Secuencia',
                      border: OutlineInputBorder(),
                    ),
                    items: _sequences.map((seq) {
                      return DropdownMenuItem(
                        value: seq,
                        child: Text(seq.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedToSequence = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _durationController,
                    decoration: const InputDecoration(
                      labelText: 'Duración del Alistamiento (minutos)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _saveSetupTime,
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar Configuración'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Lista de configuraciones existentes
          Expanded(
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Configuraciones para ${_selectedMachine?.name ?? ""}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: _setupTimes.isEmpty
                        ? const Center(
                            child:
                                Text('No hay configuraciones de alistamiento'))
                        : ListView.builder(
                            itemCount: _setupTimes.length,
                            itemBuilder: (context, index) {
                              final setupTime = _setupTimes[index];
                              final fromSeq = _sequences
                                  .where(
                                      (s) => s.id == setupTime.fromSequenceId)
                                  .firstOrNull;
                              final toSeq = _sequences
                                  .where((s) => s.id == setupTime.toSequenceId)
                                  .firstOrNull;

                              return ListTile(
                                leading: const Icon(Icons.timer),
                                title: Text(
                                  'De: ${fromSeq?.name ?? "Cualquiera"} → A: ${toSeq?.name ?? "Desconocida"}',
                                ),
                                subtitle: Text(
                                    '${setupTime.setupDuration.inMinutes} minutos'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () =>
                                      _deleteSetupTime(setupTime.id!),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }
}
