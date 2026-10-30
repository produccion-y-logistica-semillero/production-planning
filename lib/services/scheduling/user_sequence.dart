// lib/services/scheduling/user_sequence.dart
//
// The "SECUENCIA_USUARIO" rule: the user types the job order instead of
// letting a rule choose it. Permutation environments (single machine,
// flow shop, flexible flow shop, parallel machines as a priority list)
// schedule the jobs in exactly that order; shop environments (job shop,
// open shop and their flexible variants) use it as a priority list in the
// non-delay loop: among the operations that can start first, the job that
// is earlier in the user's list goes first.

/// [jobs] reordered by [sequence] (job ids). Jobs missing from the
/// sequence follow in release order, then by id, so the result always holds
/// every job exactly once.
List<T> orderByUserSequence<T>(
  List<T> jobs,
  List<int>? sequence,
  int Function(T) jobId,
  DateTime Function(T) release,
) {
  final rank = userSequenceRank(sequence);
  final out = List<T>.of(jobs);
  out.sort((a, b) => compareByUserSequence(
        rank,
        jobId(a),
        jobId(b),
        release(a),
        release(b),
      ));
  return out;
}

/// Position of each job id in [sequence] (0 = first).
Map<int, int> userSequenceRank(List<int>? sequence) => {
      if (sequence != null)
        for (int i = 0; i < sequence.length; i++) sequence[i]: i,
    };

/// Earlier in the user's list first; jobs not in the list go after all the
/// listed ones, in release order, then by id.
int compareByUserSequence(
  Map<int, int> rank,
  int jobA,
  int jobB,
  DateTime releaseA,
  DateTime releaseB,
) {
  final ra = rank[jobA];
  final rb = rank[jobB];
  if (ra != null && rb != null && ra != rb) return ra.compareTo(rb);
  if (ra != null && rb == null) return -1;
  if (ra == null && rb != null) return 1;
  final byRelease = releaseA.compareTo(releaseB);
  if (byRelease != 0) return byRelease;
  return jobA.compareTo(jobB);
}
