class MachineTypeEntity {
  int? id;
  final String name;
  final String description;
  List<MachineTypeEntity>? machines;

  MachineTypeEntity({this.id, required this.name, required this.description});

  @override
  String toString() {
    return 'MachineTypeEntity(id: $id, name: $name, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MachineTypeEntity &&
        other.id == id &&
        other.name == name &&
        other.description == description;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ description.hashCode;
}
