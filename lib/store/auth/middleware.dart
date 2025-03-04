import 'package:redux/redux.dart';
import 'package:syphon/store/events/actions.dart';
import 'package:syphon/store/index.dart';
import 'package:syphon/store/rooms/actions.dart';

///
/// Auth Middleware
///
/// Prevents firing any authenticated mutations
///
///
authMiddleware<State>(
  Store<AppState> store,
  dynamic action,
  NextDispatcher next,
) {
  switch (action.runtimeType) {
    case SetReactions:
    case SetRedactions:
    case AddMessages:
    case UpdateRoom:
      if (store.state.authStore.user.accessToken == null) {
        return;
      }
      next(action);
      break;
    default:
      next(action);
      break;
  }
}
