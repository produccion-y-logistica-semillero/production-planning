import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_state.dart';

class GanttBloc extends Bloc<GanttEvent, GanttState>{


  GanttBloc(): super(GanttInitialState());

}