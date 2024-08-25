class MachineTypeEntity{
  int? id;
  final String name;
  final String description;
  List<MachineTypeEntity>? machines;

  MachineTypeEntity({this.id, required this.name,  required this.description});
}