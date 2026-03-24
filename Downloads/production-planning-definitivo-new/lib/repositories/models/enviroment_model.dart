
class EnviromentModel{

  final int id;
  final String name;

  EnviromentModel(this.id, this.name);

  factory EnviromentModel.fromJSON(Map<String, dynamic> json){
    return EnviromentModel(
      json['environment_id'], json['name']);
  }
}