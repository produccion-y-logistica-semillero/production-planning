// lib/services/scheduling/machine_plan_text.dart
//
// Reads the two tables of the reference sheet when the user pastes them from
// a spreadsheet (copying cells from Excel gives tab-separated text):
//
//   Job   Op 1  Op 2            <- route table: first header cell is "Job"
//   J1    M1    M2
//   Máquina  Pos 1  Pos 2       <- sequence table: first header cell is
//   M1       J1     J2             "Máquina" (or "Maquina" / "Machine")
//
// Anything that is not one of those two tables (titles, notes, blank lines)
// is ignored. Names are returned as typed; the caller matches them against
// the program's jobs and machines.
class PastedMachinePlan {
  /// job name -> machine names in visit order (empty cells dropped).
  final Map<String, List<String>> routes;

  /// machine name -> job names in processing order (empty cells dropped).
  final Map<String, List<String>> sequences;

  const PastedMachinePlan(this.routes, this.sequences);

  bool get isEmpty => routes.isEmpty && sequences.isEmpty;
}

List<String> _cells(String line) {
  final String sep = line.contains('\t')
      ? '\t'
      : line.contains(';')
          ? ';'
          : line.contains(',')
              ? ','
              : '  '; // two or more spaces
  final parts = sep == '  '
      ? line.split(RegExp(r'\s{2,}'))
      : line.split(sep);
  return [for (final p in parts) p.trim()];
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .trim();

PastedMachinePlan parsePastedMachinePlan(String text) {
  final routes = <String, List<String>>{};
  final sequences = <String, List<String>>{};
  Map<String, List<String>>? current;

  for (final raw in text.split(RegExp(r'\r?\n'))) {
    if (raw.trim().isEmpty) {
      current = null;
      continue;
    }
    final cells = _cells(raw);
    final first = _norm(cells.first);
    if (first == 'job' || first == 'trabajo') {
      current = routes;
      continue;
    }
    if (first == 'maquina' || first == 'machine') {
      current = sequences;
      continue;
    }
    if (current == null || cells.first.isEmpty) continue;
    current[cells.first] = [
      for (final c in cells.skip(1))
        if (c.isNotEmpty) c,
    ];
  }
  return PastedMachinePlan(routes, sequences);
}
