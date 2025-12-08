import 'package:production_planning/entities/metrics.dart';

abstract class MetricsState {}

class MetricsInitialState extends MetricsState {}

class MetricsLoadingState extends MetricsState {}

class MetricsLoadedState extends MetricsState {
  final List<Metrics> metrics;
  final List<String> ruleNames;

  MetricsLoadedState(this.metrics, this.ruleNames);
}

class MetricsErrorState extends MetricsState {
  final String message;
  MetricsErrorState(this.message);
}
