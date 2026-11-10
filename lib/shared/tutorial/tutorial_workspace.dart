// lib/shared/tutorial/tutorial_workspace.dart
//
// The guided tutorial works in its own workspace ("Tutorial"), so what the
// user creates while learning never mixes with their real data. Entering
// it reopens the app's dependencies on a fresh Tutorial database without a
// restart; leaving it reopens the user's workspace. workspace.txt is not
// touched, so a restart always comes back to the user's own workspace.
import 'package:production_planning/shared/duration_input.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:production_planning/shared/workspace/workspace_session.dart';
import 'package:production_planning/shared/workspace/workspace_store.dart';

export 'package:production_planning/shared/workspace/workspace_session.dart'
    show appSession, appSwitching;

const String kTutorialWorkspace = kTutorialWorkspaceName;

String? _returnWorkspace;

/// True while the tutorial workspace is open.
bool get inTutorialWorkspace => _returnWorkspace != null;

/// Opens a clean tutorial workspace and starts [tour] in it. When the tour
/// ends (finished or abandoned) the user's workspace comes back.
Future<void> startGuidedTour(TutorialTour tour) async {
  if (!inTutorialWorkspace) {
    _returnWorkspace = await (await appWorkspaceStore()).currentName();
  }
  await reopenWorkspace(kTutorialWorkspace, fresh: true);
  // The tour asks for durations in minutes ("escribe 30"). Only the
  // tutorial workspace changes: the user's keeps its own format.
  await saveTimeFormat(TimeInputFormat.minutes);
  tutorial.onEnd = (_) => leaveTutorialWorkspace();
  tutorial.start(tour);
}

/// Back to the workspace that was open before the tutorial (with its own
/// shift and time format, read from its database).
Future<void> leaveTutorialWorkspace() async {
  final back = _returnWorkspace;
  if (back == null) return;
  _returnWorkspace = null;
  await reopenWorkspace(back);
}
