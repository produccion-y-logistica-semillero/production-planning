import 'package:production_planning/features/sequences/data/models/sequence_model.dart';

abstract class SequencesDao{
  Future<int> createSequence(SequenceModel sequence);
}