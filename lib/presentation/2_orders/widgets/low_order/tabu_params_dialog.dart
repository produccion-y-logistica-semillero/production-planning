import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:production_planning/entities/tabu_params.dart';

/// Dialogo de configuracion de la busqueda tabu.
/// Devuelve un [TabuParams] al aceptar, o null si el usuario cancela.
class TabuParamsDialog extends StatefulWidget {
  final TabuParams initial;

  const TabuParamsDialog({super.key, this.initial = const TabuParams()});

  @override
  State<TabuParamsDialog> createState() => _TabuParamsDialogState();
}

class _TabuParamsDialogState extends State<TabuParamsDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _maxIterations;
  late final TextEditingController _intraAttempts;
  late final TextEditingController _interJobSamples;
  late final TextEditingController _maxDestinations;
  late final TextEditingController _timeBudgetMs;
  late bool _randomStart;

  @override
  void initState() {
    super.initState();
    _maxIterations =
        TextEditingController(text: '${widget.initial.maxIterations}');
    _intraAttempts =
        TextEditingController(text: '${widget.initial.intraAttempts}');
    _interJobSamples =
        TextEditingController(text: '${widget.initial.interJobSamples}');
    _maxDestinations =
        TextEditingController(text: '${widget.initial.maxDestinations}');
    _timeBudgetMs =
        TextEditingController(text: '${widget.initial.timeBudgetMs}');
    _randomStart = widget.initial.randomStart;
  }

  @override
  void dispose() {
    _maxIterations.dispose();
    _intraAttempts.dispose();
    _interJobSamples.dispose();
    _maxDestinations.dispose();
    _timeBudgetMs.dispose();
    super.dispose();
  }

  String? _validate(String? value, int min, int max) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null) return 'Ingrese un numero entero';
    if (parsed < min || parsed > max) return 'Debe estar entre $min y $max';
    return null;
  }

  Widget _field({
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
        validator: (v) => _validate(v, min, max),
      ),
    );
  }

  void _restoreDefaults() {
    const d = TabuParams();
    _maxIterations.text = '${d.maxIterations}';
    _intraAttempts.text = '${d.intraAttempts}';
    _interJobSamples.text = '${d.interJobSamples}';
    _maxDestinations.text = '${d.maxDestinations}';
    _timeBudgetMs.text = '${d.timeBudgetMs}';
    setState(() => _randomStart = d.randomStart);
    _formKey.currentState?.validate();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(TabuParams(
      maxIterations: int.parse(_maxIterations.text.trim()),
      intraAttempts: int.parse(_intraAttempts.text.trim()),
      interJobSamples: int.parse(_interJobSamples.text.trim()),
      maxDestinations: int.parse(_maxDestinations.text.trim()),
      timeBudgetMs: int.parse(_timeBudgetMs.text.trim()),
      randomStart: _randomStart,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Parametros de la busqueda tabu'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(
                  controller: _maxIterations,
                  label: 'Tope de iteraciones',
                  helper: 'Cuantas iteraciones puede hacer el bucle principal.',
                  min: 1,
                  max: 20000,
                ),
                _field(
                  controller: _intraAttempts,
                  label: 'Intentos rama intra-maquina',
                  helper: 'Reubicaciones que prueba dentro de una misma '
                      'maquina antes de abandonar la rama.',
                  min: 1,
                  max: 5000,
                ),
                _field(
                  controller: _interJobSamples,
                  label: 'Jobs considerados (inter-maquina)',
                  helper: 'Cuantos jobs, de mayor a menor retraso, intenta '
                      'mover a otra maquina.',
                  min: 1,
                  max: 1000,
                ),
                _field(
                  controller: _maxDestinations,
                  label: 'Maquinas destino por job',
                  helper: 'Maquinas alternativas que prueba cada job movido.',
                  min: 1,
                  max: 50,
                ),
                _field(
                  controller: _timeBudgetMs,
                  label: 'Presupuesto de tiempo (ms)',
                  helper: 'Corta la busqueda al agotarse, aunque queden '
                      'iteraciones. Es el freno real.',
                  min: 100,
                  max: 600000,
                ),
                const Divider(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Arranque aleatorio'),
                  subtitle: Text(
                    _randomStart
                        ? 'Parte de una asignacion al azar. Solo para '
                            'diagnostico: mide cuanto aporta el tabu por si '
                            'solo. El resultado puede ser peor.'
                        : 'Parte de la mejor de las 9 reglas de despacho. '
                            'Modo recomendado.',
                  ),
                  isThreeLine: _randomStart,
                  value: _randomStart,
                  onChanged: (v) => setState(() => _randomStart = v),
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
        FilledButton(onPressed: _submit, child: const Text('Guardar Configuracion')),
      ],
    );
  }
}