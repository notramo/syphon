import 'dart:async';
import 'dart:convert';

import 'package:sembast/sembast.dart';
import 'package:syphon/global/print.dart';
import 'package:syphon/storage/constants.dart';
import 'package:syphon/store/events/model.dart';
import 'package:syphon/store/events/messages/model.dart';
import 'package:syphon/store/events/reactions/model.dart';
import 'package:syphon/store/events/redaction/model.dart';

Future<void> saveEvents(
  List<Event> events, {
  required Database storage,
}) async {
  final store = StoreRef<String?, String>(StorageKeys.EVENTS);

  return storage.transaction((txn) async {
    for (final Event event in events) {
      final record = store.record(event.id);
      await record.put(txn, json.encode(event));
    }
  });
}

Future<void> deleteEvents(
  List<Event> events, {
  Database? storage,
}) async {
  final stores = [
    StoreRef<String?, String>(StorageKeys.MESSAGES),
    StoreRef<String?, String>(StorageKeys.REACTIONS),
  ];

  await Future.wait(stores.map((store) async {
    return storage!.transaction((txn) async {
      for (final Event event in events) {
        final record = store.record(event.id);
        await record.delete(storage);
      }
    });
  }));
}

///
/// Save Redactions
///
/// Saves redactions to a map keyed by
/// event ids of redacted events
///
Future<void> saveRedactions(
  List<Redaction> redactions, {
  required Database storage,
}) async {
  try {
    final store = StoreRef<String?, String>(StorageKeys.REDACTIONS);

    return await storage.transaction((txn) async {
      for (final Redaction redaction in redactions) {
        final record = store.record(redaction.redactId);
        await record.put(txn, json.encode(redaction));
      }
    });
  } catch (error) {
    printError('[saveRedactions] $error');
    rethrow;
  }
}

///
/// Load Redactions
///
/// Load all the redactions from storage
/// filtering should occur shortly after in
/// another parser/filter/selector
///
Future<Map<String, Redaction>> loadRedactions({
  required Database storage,
}) async {
  final store = StoreRef<String, String>(StorageKeys.REDACTIONS);

  final redactions = <String, Redaction>{};

  final redactionsData = await store.find(storage);

  for (final RecordSnapshot<String, String> record in redactionsData) {
    redactions[record.key] = Redaction.fromJson(
      json.decode(record.value),
    );
  }

  return redactions;
}

///
/// Save Reactions
///
/// Saves reactions to storage by the related/associated message id
/// this allows calls to fetch reactions from cold storage to be
/// O(1) referenced by map keys, also prevents additional key references
/// to the specific reaction in other objects
///
Future<void> saveReactions(
  List<Reaction> reactions, {
  required Database storage,
}) async {
  try {
    final store = StoreRef<String?, String>(StorageKeys.REACTIONS);

    return await storage.transaction((txn) async {
      for (final Reaction reaction in reactions) {
        if (reaction.relEventId != null) {
          final record = store.record(reaction.relEventId);
          final exists = await record.exists(storage);

          var reactionsUpdated = [reaction];

          if (exists) {
            final existingRaw = await record.get(storage);
            final existingJson = List.from(await json.decode(existingRaw!));
            final existingList = List.from(existingJson.map(
              (json) => Reaction.fromJson(json),
            ));

            final exists = existingList.any(
              (existing) => existing.id == reaction.id,
            );

            if (!exists) {
              reactionsUpdated = [...existingList, reaction];
            }
          }

          await record.put(txn, json.encode(reactionsUpdated));
        }
      }
    });
  } catch (error) {
    printError('[saveReactions] $error');
    rethrow;
  }
}

///
/// Load Reactions
///
/// Loads reactions from storage by the related/associated message id
/// this done with O(1) by reference with message ids being the key
///
Future<Map<String, List<Reaction>>> loadReactions(
  List<String?> messageIds, {
  required Database storage,
}) async {
  try {
    final store = StoreRef<String?, String>(StorageKeys.REACTIONS);
    final reactionsMap = <String, List<Reaction>>{};
    final reactionsRecords = await store.records(messageIds).getSnapshots(storage);

    for (final RecordSnapshot<String?, String>? reactionList in reactionsRecords) {
      if (reactionList != null) {
        final reactions =
            List.from(await json.decode(reactionList.value)).map((json) => Reaction.fromJson(json)).toList();
        reactionsMap.putIfAbsent(reactionList.key!, () => reactions);
      }
    }

    return reactionsMap;
  } catch (error) {
    printError(error.toString());
    return {};
  }
}

///
/// Save Messages (Cold Storage)
///
/// In storage, messages are indexed by eventId
/// In redux, they're indexed by RoomID and placed in a list
///
Future<void> saveMessages(
  List<Message> messages, {
  required Database storage,
}) async {
  final store = StoreRef<String?, String>(StorageKeys.MESSAGES);

  return storage.transaction((txn) async {
    for (final Message message in messages) {
      final record = store.record(message.id);
      await record.put(txn, json.encode(message));
    }
  });
}

///
/// Load Messages (Cold Storage)
///
/// In storage, messages are indexed by eventId
/// In redux, they're indexed by RoomID and placed in a list
Future<List<Message>> loadMessages(
  List<String> eventIds, {
  required Database storage,
  int offset = 0,
  int limit = 20, // default amount loaded
}) async {
  final List<Message> messages = [];

  try {
    final store = StoreRef<String?, String>(StorageKeys.MESSAGES);

    // TODO: properly paginate through cold storage messages instead of loading all
    final messageIds = eventIds; //.skip(offset).take(limit).toList();

    final messagesPaginated = await store.records(messageIds).get(storage);

    for (final String? message in messagesPaginated) {
      if (message != null) {
        messages.add(Message.fromJson(json.decode(message)));
      }
    }

    return messages;
  } catch (error) {
    printError(error.toString(), title: 'loadMessages');
    return [];
  }
}

///
/// Save Decrypted (Cold Storage)
///
/// In storage, messages are indexed by eventId
/// In redux, they're indexed by RoomID and placed in a list
///
/// TODO: remove when room previews are cached alongside rooms
/// *** should be able to backfill room encryption before a user can
/// *** peek at a room and not need to save decrypted messages, as long
/// *** as we have a room preview. Will buy Syphon several hundred millis to
/// *** decode the message
///
Future<void> saveDecrypted(
  List<Message> messages, {
  required Database storage,
}) async {
  final store = StoreRef<String?, String>(StorageKeys.DECRYPTED);

  return storage.transaction((txn) async {
    for (final Message message in messages) {
      final record = store.record(message.id);
      await record.put(txn, json.encode(message));
    }
  });
}

///
/// Load Decrypted (Cold Storage)
///
/// In storage, messages are indexed by eventId
/// In redux, they're indexed by RoomID and placed in a list
///
/// /// TODO: remove when room previews are cached alongside rooms
/// *** should be able to backfill room encryption before a user can
/// *** peek at a room and not need to save decrypted messages, as long
/// *** as we have a room preview. Will buy Syphon several hundred millis to
/// *** decode the message
Future<List<Message>> loadDecrypted(
  List<String> eventIds, {
  required Database storage,
  int offset = 0,
  int limit = 20, // default amount loaded
}) async {
  final List<Message> messages = [];

  try {
    final store = StoreRef<String?, String>(StorageKeys.DECRYPTED);

    // TODO: properly paginate through cold storage messages instead of loading all
    final messageIds = eventIds; //.skip(offset).take(limit).toList();

    final messagesPaginated = await store.records(messageIds).get(storage);

    for (final String? message in messagesPaginated) {
      if (message != null) {
        messages.add(Message.fromJson(json.decode(message)));
      }
    }

    return messages;
  } catch (error) {
    printError(error.toString(), title: 'loadMessages');
    return [];
  }
}
