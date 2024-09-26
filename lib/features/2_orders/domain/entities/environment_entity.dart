class EnvironmentEntity{
  final int environmentId;
  final String name;
  Map<int, String> rules;

  EnvironmentEntity(
    this.environmentId,
    this.name,
    this.rules
  );
}