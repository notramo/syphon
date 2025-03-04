import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:redux/redux.dart';
import 'package:redux_thunk/redux_thunk.dart';

import 'package:syphon/global/libs/matrix/index.dart';
import 'package:syphon/store/alerts/actions.dart';
import 'package:syphon/store/crypto/actions.dart';
import 'package:syphon/store/crypto/events/actions.dart';
import 'package:syphon/store/events/actions.dart';
import 'package:syphon/store/events/selectors.dart';
import 'package:syphon/store/index.dart';
import 'package:syphon/store/rooms/actions.dart';
import 'package:syphon/global/libs/matrix/constants.dart';
import 'package:syphon/store/events/messages/model.dart';
import 'package:syphon/store/rooms/room/model.dart';

///
/// Mutate Messages
///
/// Add/mutate to accomodate all the required, necessary
/// mutations by matrix after the message has been sent
/// such as reactions, redactions, and edits
///
ThunkAction<AppState> mutateMessages({List<Message>? messages}) {
  return (Store<AppState> store) async {
    final reactions = store.state.eventStore.reactions;
    final redactions = store.state.eventStore.redactions;

    final revisedMessages = await compute(reviseMessagesBackground, {
      'reactions': reactions,
      'redactions': redactions,
      'messages': messages,
    });

    return revisedMessages;
  };
}

///
/// Mutate Messages All
///
/// Add/mutate to accomodate all messages avaiable with
/// the required, necessary mutations by matrix after the
/// message has been sent (such as reactions, redactions, and edits)
///
ThunkAction<AppState> mutateMessagesAll() {
  return (Store<AppState> store) async {
    final rooms = store.state.roomStore.roomList;

    await Future.wait(rooms.map((room) async {
      try {
        await store.dispatch(mutateMessagesRoom(room: room));
      } catch (error) {
        debugPrint('[mutateMessagesAll] error ${room.id} ${error.toString()}');
      }
    }));
  };
}

///
/// Mutate Messages All
///
/// Run through all room messages to accomodate the required,
/// necessary mutations by matrix after the message has been sent
/// such as reactions, redactions, and edits
///
ThunkAction<AppState> mutateMessagesRoom({required Room room}) {
  return (Store<AppState> store) async {
    if (room.messagesNew.isEmpty) return;

    final messages = store.state.eventStore.messages[room.id];
    final decrypted = store.state.eventStore.messagesDecrypted[room.id];
    final reactions = store.state.eventStore.reactions;
    final redactions = store.state.eventStore.redactions;

    final mutations = [
      compute(reviseMessagesBackground, {
        'reactions': reactions,
        'redactions': redactions,
        'messages': messages,
      })
    ];

    if (room.encryptionEnabled) {
      mutations.add(compute(reviseMessagesBackground, {
        'reactions': reactions,
        'redactions': redactions,
        'messages': decrypted,
      }));
    }

    final messagesLists = await Future.wait(mutations);

    if (room.encryptionEnabled) {
      await store.dispatch(addMessagesDecrypted(
        room: Room(id: room.id),
        messages: messagesLists[1],
      ));
    }

    await store.dispatch(addMessages(
      room: Room(id: room.id),
      messages: messagesLists[0],
    ));
  };
}

/// Send Message
ThunkAction<AppState> sendMessage({
  required Room room,
  required Message message,
}) {
  return (Store<AppState> store) async {
    try {
      store.dispatch(UpdateRoom(id: room.id, sending: true));

      // if you're incredibly unlucky, and fast, you could have a problem here
      final tempId = Random.secure().nextInt(1 << 32).toString();
      final reply = store.state.roomStore.rooms[room.id]!.reply;

      // trim trailing whitespace
      message = message.copyWith(body: message.body!.trimRight());

      // pending outbox message
      Message pending = Message(
        id: tempId,
        body: message.body,
        type: message.type,
        content: {
          'body': message.body,
          'msgtype': message.type ?? MessageTypes.TEXT,
        },
        sender: store.state.authStore.user.userId,
        roomId: room.id,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        pending: true,
        syncing: true,
      );

      if (reply != null && reply.body != null) {
        pending = await store.dispatch(
          formatMessageReply(room, pending, reply),
        );
      }

      // Save unsent message to outbox
      store.dispatch(SaveOutboxMessage(
        tempId: tempId,
        pendingMessage: pending,
      ));

      final data = await MatrixApi.sendMessage(
        protocol: store.state.authStore.protocol,
        homeserver: store.state.authStore.user.homeserver,
        accessToken: store.state.authStore.user.accessToken,
        roomId: room.id,
        message: pending.content,
        trxId: DateTime.now().millisecond.toString(),
      );

      if (data['errcode'] != null) {
        store.dispatch(SaveOutboxMessage(
          tempId: tempId,
          pendingMessage: pending.copyWith(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            pending: false,
            syncing: false,
            failed: true,
          ),
        ));

        throw data['error'];
      }

      // Update sent message with event id but needs
      // to be syncing to remove from outbox
      store.dispatch(SaveOutboxMessage(
        tempId: tempId,
        pendingMessage: pending.copyWith(
          id: data['event_id'],
          timestamp: DateTime.now().millisecondsSinceEpoch,
          syncing: true,
        ),
      ));

      return true;
    } catch (error) {
      store.dispatch(addAlert(
        error: error,
        message: error.toString(),
        origin: 'sendMessage',
      ));
      return false;
    } finally {
      store.dispatch(UpdateRoom(
        id: room.id,
        sending: false,
        reply: Message(),
      ));
    }
  };
}

/// Send Encrypted Messages
///
/// Specifically for sending encrypted messages using megolm
ThunkAction<AppState> sendMessageEncrypted({
  required String roomId,
  required Message message, // body and type only for now
}) {
  return (Store<AppState> store) async {
    try {
      final room = store.state.roomStore.rooms[roomId]!;

      store.dispatch(UpdateRoom(id: room.id, sending: true));

      // send the key session - if one hasn't been sent
      // or created - to every user within the room
      await store.dispatch(updateKeySessions(room: room));

      // Save unsent message to outbox
      final tempId = Random.secure().nextInt(1 << 32).toString();
      final reply = store.state.roomStore.rooms[room.id]!.reply;

      // trim trailing whitespace
      message = message.copyWith(body: message.body!.trimRight());

      // pending outbox message
      Message pending = Message(
        id: tempId,
        roomId: room.id,
        body: message.body,
        type: message.type,
        content: {
          'body': message.body,
          'msgtype': message.type ?? MessageTypes.TEXT,
        },
        sender: store.state.authStore.user.userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        pending: true,
        syncing: true,
      );

      final unencryptedData = {};

      if (reply != null && reply.body != null) {
        pending = await store.dispatch(
          formatMessageReply(room, pending, reply),
        );
        unencryptedData['m.relates_to'] = {
          'm.in_reply_to': {'event_id': '${reply.id}'}
        };
      }

      store.dispatch(SaveOutboxMessage(
        tempId: tempId,
        pendingMessage: pending,
      ));

      // Encrypt the message event
      final encryptedEvent = await store.dispatch(
        encryptMessageContent(
          roomId: room.id,
          content: pending.content,
          eventType: EventTypes.message,
        ),
      );

      final data = await MatrixApi.sendMessageEncrypted(
        protocol: store.state.authStore.protocol,
        homeserver: store.state.authStore.user.homeserver,
        unencryptedData: unencryptedData,
        accessToken: store.state.authStore.user.accessToken,
        trxId: DateTime.now().millisecond.toString(),
        roomId: room.id,
        senderKey: encryptedEvent['sender_key'],
        ciphertext: encryptedEvent['ciphertext'],
        sessionId: encryptedEvent['session_id'],
        deviceId: store.state.authStore.user.deviceId,
      );

      if (data['errcode'] != null) {
        store.dispatch(SaveOutboxMessage(
          tempId: tempId,
          pendingMessage: pending.copyWith(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            pending: false,
            syncing: false,
            failed: true,
          ),
        ));

        throw data['error'];
      }

      store.dispatch(SaveOutboxMessage(
        tempId: tempId,
        pendingMessage: pending.copyWith(
          id: data['event_id'],
          timestamp: DateTime.now().millisecondsSinceEpoch,
          syncing: true,
        ),
      ));

      return true;
    } catch (error) {
      store.dispatch(
        addAlert(
          error: error,
          message: error.toString(),
          origin: 'sendMessageEncrypted',
        ),
      );
      return false;
    } finally {
      store.dispatch(UpdateRoom(id: roomId, sending: false, reply: Message()));
    }
  };
}
