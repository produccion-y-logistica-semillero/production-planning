/// Lo que el usuario configura en el selector de algoritmos ademas de las
/// reglas: parametros de TABU, parametros del genetico y una secuencia
/// propia de trabajos. Viaja igual que antes viajaba solo [TabuParams]:
/// selector -> metricas / Gantt -> OrdersService -> adapters -> algoritmos.
import 'package:production_planning/entities/genetic_params.dart';
import 'package:production_planning/entities/tabu_params.dart';

/// Nombre de la "regla" que programa la secuencia del usuario. No esta en
/// la base de datos: el selector la agrega cuando el usuario define un orden.
const String kUserSequenceRule = 'SECUENCIA_USUARIO';

/// Id con el que la secuencia del usuario aparece entre las reglas (no
/// choca con ningun id de la tabla dispatch_rules).
const int kUserSequenceRuleId = -1;

class AlgorithmParams {
  final TabuParams? tabu;
  final GeneticParams? genetic;

  /// Ids de los trabajos (jobId de la base de datos) en el orden que eligio
  /// el usuario. Null si no definio secuencia.
  final List<int>? userSequence;

  const AlgorithmParams({this.tabu, this.genetic, this.userSequence});

  AlgorithmParams copyWith({
    TabuParams? tabu,
    GeneticParams? genetic,
    List<int>? userSequence,
  }) {
    return AlgorithmParams(
      tabu: tabu ?? this.tabu,
      genetic: genetic ?? this.genetic,
      userSequence: userSequence ?? this.userSequence,
    );
  }
}
