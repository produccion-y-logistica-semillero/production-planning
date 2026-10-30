import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:production_planning/entities/genetic_params.dart';
import 'package:production_planning/entities/schedule_objective.dart';

/// Dialogo de configuracion del algoritmo genetico (GENETICS), con el mismo
/// formato que el de la busqueda tabu. Devuelve un [GeneticParams] al
/// aceptar, o null si el usuario cancela.
class GeneticParamsDialog extends StatefulWidget {
  final GeneticParams initial;

  const GeneticParamsDialog({super.key, this.initial = const GeneticParams()});

  @override
  State<GeneticParamsDialog> createState() => _GeneticParamsDialogState();
}

class _GeneticParamsDialogState extends State<GeneticParamsDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _populationSize;
  late final TextEditingController _maxGenerations;
  late final TextEditingController _stallGenerations;
  late final TextEditingController _tournamentSize;
  late final TextEditingController _crossoverRate;
  late final TextEditingController _mutationRate;
  late final TextEditingController _elitism;
  late final TextEditingController _seed;
  late ScheduleObjective _objective;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _populationSize = TextEditingController(text: '${p.populationSize}');
    _maxGenerations = TextEditingController(text: '${p.maxGenerations}');
    _stallGenerations = TextEditingController(text: '${p.stallGenerations}');
    _tournamentSize = TextEditingController(text: '${p.tournamentSize}');
    _crossoverRate = TextEditingController(text: '${p.crossoverRate}');
    _mutationRate = TextEditingController(text: '${p.mutationRate}');
    _elitism = TextEditingController(text: '${p.elitism}');
    _seed = TextEditingController(text: '${p.seed}');
    _objective = p.objective;
  }

  @override
  void dispose() {
    _populationSize.dispose();
    _maxGenerations.dispose();
    _stallGenerations.dispose();
    _tournamentSize.dispose();
    _crossoverRate.dispose();
    _mutationRate.dispose();
    _elitism.dispose();
    _seed.dispose();
    super.dispose();
  }

  String? _validateInt(String? value, int min, int max) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null) return 'Ingrese un numero entero';
    if (parsed < min || parsed > max) return 'Debe estar entre $min y $max';
    return null;
  }

  String? _validateRate(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (parsed == null) return 'Ingrese un numero (ej. 0.8)';
    if (parsed < 0 || parsed > 1) return 'Debe estar entre 0 y 1';
    return null;
  }

  double _rate(TextEditingController c) =>
      double.parse(c.text.trim().replaceAll(',', '.'));

  Widget _intField({
    required TextEditingController controller,
    required String label,
    required String helper,
    required int min,
    required int max,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: (v) => _validateInt(v, min, max),
      ),
    );
  }

  Widget _rateField({
    required TextEditingController controller,
    required String label,
    required String helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: _validateRate,
      ),
    );
  }

  /// Selector de la funcion objetivo, igual al de la busqueda tabu.
  Widget _objectiveSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Funcion objetivo',
          helperText: 'Lo que minimiza el algoritmo al comparar '
              'individuos (secuencias).',
          helperMaxLines: 3,
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<ScheduleObjective>(
            value: _objective,
            isExpanded: true,
            isDense: true,
            items: [
              for (final objective in ScheduleObjective.values)
                DropdownMenuItem<ScheduleObjective>(
                  value: objective,
                  child: Text('${objective.label}  ·  ${objective.formula}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _objective = v);
            },
          ),
        ),
      ),
    );
  }

  void _restoreDefaults() {
    const d = GeneticParams();
    _populationSize.text = '${d.populationSize}';
    _maxGenerations.text = '${d.maxGenerations}';
    _stallGenerations.text = '${d.stallGenerations}';
    _tournamentSize.text = '${d.tournamentSize}';
    _crossoverRate.text = '${d.crossoverRate}';
    _mutationRate.text = '${d.mutationRate}';
    _elitism.text = '${d.elitism}';
    _seed.text = '${d.seed}';
    setState(() => _objective = d.objective);
    _formKey.currentState?.validate();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final population = int.parse(_populationSize.text.trim());
    final elitism = int.parse(_elitism.text.trim());
    if (elitism >= population) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El elitismo debe ser menor que la poblacion.'),
      ));
      return;
    }
    Navigator.of(context).pop(GeneticParams(
      populationSize: population,
      maxGenerations: int.parse(_maxGenerations.text.trim()),
      stallGenerations: int.parse(_stallGenerations.text.trim()),
      tournamentSize: int.parse(_tournamentSize.text.trim()),
      crossoverRate: _rate(_crossoverRate),
      mutationRate: _rate(_mutationRate),
      elitism: elitism,
      seed: int.parse(_seed.text.trim()),
      objective: _objective,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Parametros del algoritmo genetico'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _objectiveSelector(),
                _intField(
                  controller: _populationSize,
                  label: 'Tamano de la poblacion',
                  helper: 'Secuencias que conviven en cada generacion.',
                  min: 2,
                  max: 500,
                ),
                _intField(
                  controller: _maxGenerations,
                  label: 'Numero de generaciones',
                  helper: 'Tope de generaciones que se crean.',
                  min: 1,
                  max: 5000,
                ),
                _intField(
                  controller: _stallGenerations,
                  label: 'Generaciones sin mejora',
                  helper: 'Se detiene si el mejor individuo no mejora en '
                      'este numero de generaciones seguidas.',
                  min: 1,
                  max: 5000,
                ),
                _intField(
                  controller: _tournamentSize,
                  label: 'Tamano del torneo',
                  helper: 'Individuos que compiten para ser padre; mas grande '
                      'presiona mas hacia los mejores.',
                  min: 1,
                  max: 50,
                ),
                _rateField(
                  controller: _crossoverRate,
                  label: 'Probabilidad de cruce (0-1)',
                  helper: 'Probabilidad de combinar dos padres; si no, el '
                      'hijo es copia del primero.',
                ),
                _rateField(
                  controller: _mutationRate,
                  label: 'Probabilidad de mutacion (0-1)',
                  helper: 'Probabilidad de mover un trabajo (u operacion) a '
                      'otra posicion en el hijo.',
                ),
                _intField(
                  controller: _elitism,
                  label: 'Elitismo',
                  helper: 'Mejores individuos que pasan intactos a la '
                      'siguiente generacion.',
                  min: 0,
                  max: 100,
                ),
                _intField(
                  controller: _seed,
                  label: 'Semilla aleatoria',
                  helper: 'Con la misma semilla y los mismos datos se obtiene '
                      'siempre el mismo resultado.',
                  min: 0,
                  max: 2147483647,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _restoreDefaults, child: const Text('Restaurar')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
            onPressed: _submit, child: const Text('Guardar Configuracion')),
      ],
    );
  }
}
