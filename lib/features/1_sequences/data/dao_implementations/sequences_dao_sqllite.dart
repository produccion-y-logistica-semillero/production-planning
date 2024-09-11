import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/sequences_dao.dart';
import 'package:production_planning/features/1_sequences/data/models/sequence_model.dart';
import 'package:sqflite/sqflite.dart';

class SequencesDaoSqllite implements SequencesDao{

  final Database db;
  SequencesDaoSqllite(this.db);

  @override
  Future<int> createSequence(SequenceModel sequence)async {
    try{
      int id = await db.insert("SEQUENCES", sequence.toJson());
      return id;
    }catch(e){
      throw LocalStorageFailure();
    }
  }
  
}