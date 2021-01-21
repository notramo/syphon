// Project imports:
import 'package:syphon/store/events/reactions/model.dart';

import './actions.dart';
import '../events/model.dart';
import './state.dart';
import 'package:syphon/store/events/messages/model.dart';

EventStore eventReducer(
    [EventStore state = const EventStore(), dynamic action]) {
  switch (action.runtimeType) {
    case SetEvents:
      final roomId = action.roomId;
      final events = Map<String, List<Event>>.from(state.events);
      events[roomId] = action.state;
      return state.copyWith(events: events);

    case SetReactions:
      final reactionsUpdated = Map<String, List<Reaction>>.from(
        state.reactions,
      );

      for (Reaction reaction in action.reactions ?? []) {
        final exists = reactionsUpdated.containsKey(reaction.relEventId);

        if (exists) {
          final existing = reactionsUpdated[reaction.relEventId];
          if (existing.indexWhere((value) => value.id == reaction.id) == -1) {
            reactionsUpdated[reaction.relEventId] = [...existing, reaction];
          }
        } else {
          reactionsUpdated[reaction.relEventId] = [reaction];
        }
      }

      return state.copyWith(
        reactions: reactionsUpdated,
      );
    case SetMessages:
      final roomId = action.roomId;
      final messages = Map<String, List<Message>>.from(state.messages);
      final messagesOld = Map<String, Message>.fromIterable(
        messages[roomId] ?? [],
        key: (msg) => msg.id,
        value: (msg) => msg,
      );
      final messagesNew = Map<String, Message>.fromIterable(
        action.messages ?? [],
        key: (msg) => msg.id,
        value: (msg) => msg,
      );

      final messagesAll = messagesOld..addAll(messagesNew);

      messages[roomId] = messagesAll.values.toList();

      return state.copyWith(messages: messages);

    case ResetEvents:
      return EventStore();
    default:
      return state;
  }
}
