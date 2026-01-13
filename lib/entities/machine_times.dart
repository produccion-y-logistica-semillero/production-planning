class MachineTimes {
  final Duration processing;
  final Duration preparation;
  final Duration rest;

  MachineTimes({
    required this.processing,
    required this.preparation,
    required this.rest,
  });

  factory MachineTimes.fromMinutesMap(Map<String, int> m) {
    return MachineTimes(
      processing: Duration(minutes: m['processing'] ?? 0),
      preparation: Duration(minutes: m['preparation'] ?? 0),
      rest: Duration(minutes: m['rest'] ?? 0),
    );
  }

  Map<String, int> toMinutesMap() {
    return {
      'processing': processing.inMinutes,
      'preparation': preparation.inMinutes,
      'rest': rest.inMinutes,
    };
  }
}
