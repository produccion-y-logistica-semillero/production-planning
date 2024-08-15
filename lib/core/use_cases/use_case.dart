abstract class UseCase<ReturnT,  Params>{
  Future<ReturnT> call({Params p});
}