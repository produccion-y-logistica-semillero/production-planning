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

  /// Secuencia por maquina (machineId -> jobIds en el orden en que la
  /// maquina los procesa), para ambientes donde la secuencia cambia por
  /// maquina (Job Shop, Open Shop, Recurrente y sus variantes flexibles).
  /// Es estricta: cada maquina respeta exactamente su lista. Null si no la
  /// definio.
  final Map<int, List<int>>? machineSequences;

  /// Ruta decidida por el usuario (jobId -> machineIds visitadas en orden,
  /// una por operacion), donde la ruta es parte de la solucion (Open Shop).
  /// Solo se usa junto con [machineSequences].
  final Map<int, List<int>>? userRoutes;

  const AlgorithmParams({
    this.tabu,
    this.genetic,
    this.userSequence,
    this.machineSequences,
    this.userRoutes,
  });

  /// Si hay algo que programar como "secuencia del usuario" (orden de jobs o
  /// secuencia por maquina): activa la regla [kUserSequenceRule].
  bool get hasUserSequence => userSequence != null || machineSequences != null;

  AlgorithmParams copyWith({
    TabuParams? tabu,
    GeneticParams? genetic,
    List<int>? userSequence,
    Map<int, List<int>>? machineSequences,
    Map<int, List<int>>? userRoutes,
  }) {
    return AlgorithmParams(
      tabu: tabu ?? this.tabu,
      genetic: genetic ?? this.genetic,
      userSequence: userSequence ?? this.userSequence,
      machineSequences: machineSequences ?? this.machineSequences,
      userRoutes: userRoutes ?? this.userRoutes,
    );
  }
}
