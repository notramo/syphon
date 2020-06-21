import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Tether/global/algos.dart';
import 'package:Tether/global/libs/hive/index.dart';
import 'package:Tether/global/libs/matrix/errors.dart';
import 'package:Tether/global/libs/matrix/index.dart';
import 'package:Tether/store/crypto/actions.dart';
import 'package:Tether/store/sync/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:redux/redux.dart';
import 'package:redux_thunk/redux_thunk.dart';
import 'package:Tether/store/rooms/actions.dart';

import 'package:Tether/store/index.dart';

final protocol = DotEnv().env['PROTOCOL'];

class SetLoading {
  final bool loading;
  SetLoading({this.loading});
}

class SetBackoff {
  final int backoff;
  SetBackoff({this.backoff});
}

class SetOffline {
  final bool offline;
  SetOffline({this.offline});
}

class SetSyncing {
  final bool syncing;
  SetSyncing({this.syncing});
}

class SetSynced {
  final bool synced;
  final bool syncing;
  final String lastSince;
  final int backoff;

  SetSynced({
    this.synced,
    this.syncing,
    this.lastSince,
    this.backoff,
  });
}

class SetSyncObserver {
  final Timer syncObserver;
  SetSyncObserver({this.syncObserver});
}

class ResetSync {
  ResetSync();
}

/**
 * Default Room Sync Observer
 * 
 * This will be run after the initial sync. Following login or signup, users
 * will just have an observer that runs every second or so to sync with the server
 * only while the app is _active_ otherwise, it will be up to a background service
 * and a notification service to trigger syncs
 */
ThunkAction<AppState> startSyncObserver() {
  return (Store<AppState> store) async {
    final interval = store.state.syncStore.interval;

    Timer syncObserver = Timer.periodic(
      Duration(seconds: interval),
      (timer) async {
        if (store.state.syncStore.lastSince == null) {
          print('[Sync Observer] skipping sync, needs full sync');
          return;
        }

        final backoff = store.state.syncStore.backoff;
        final lastAttempt = DateTime.fromMillisecondsSinceEpoch(
          store.state.syncStore.lastAttempt,
        );

        if (backoff != null) {
          final backoffs = fibonacci(backoff);
          final backoffFactor = backoffs[backoffs.length - 1];
          final backoffLimit = DateTime.now().difference(lastAttempt).compareTo(
                Duration(milliseconds: 1000 * backoffFactor),
              );

          print(
            '[Sync Observer] backoff at ${DateTime.now().difference(lastAttempt)} of $backoffFactor',
          );

          if (backoffLimit == 1) {
            print('[Sync Observer] forced retry timeout');
            store.dispatch(fetchSync(
              since: store.state.syncStore.lastSince,
            ));
          }

          return;
        }

        if (store.state.syncStore.syncing) {
          print('[Sync Observer] still syncing');
          return;
        }

        print('[Sync Observer] running sync');
        store.dispatch(fetchSync(since: store.state.syncStore.lastSince));
      },
    );

    store.dispatch(SetSyncObserver(syncObserver: syncObserver));
  };
}

/**
 * Stop Sync Observer 
 * 
 * Will prevent the app from syncing with the homeserver 
 * every few seconds
 */
ThunkAction<AppState> stopSyncObserver() {
  return (Store<AppState> store) async {
    if (store.state.syncStore.syncObserver != null) {
      store.state.syncStore.syncObserver.cancel();
      store.dispatch(SetSyncObserver(syncObserver: null));
    }
  };
}

/**
 * Initial Sync - Custom Solution for /sync
 * 
 * This will only be run on log in because the matrix protocol handles
 * initial syncing terribly. It's incredibly cumbersome to load thousands of events
 * for multiple rooms all at once in order to show the user just some room names
 * and timestamps. Lazy loading isn't always supported, so it's not a solid solution
 */
ThunkAction<AppState> initialSync() {
  return (Store<AppState> store) async {
    // Start initial sync in background
    store.dispatch(fetchSync());

    // Fetch All Room Ids
    await store.dispatch(fetchRooms());
    await store.dispatch(fetchDirectRooms());
  };
}

/**
 * 
 * Fetch Sync
 * 
 * Responsible for updates based on differences from Matrix
 *  
 */
ThunkAction<AppState> fetchSync({String since, bool forceFull = false}) {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetSyncing(syncing: true));
      final isFullSync = since == null;
      if (isFullSync) {
        print('[fetchSync] fetching full sync');
      }

      // Matrix Sync to homeserver
      final data = await compute(MatrixApi.syncBackground, {
        'protocol': protocol,
        'homeserver': store.state.authStore.user.homeserver,
        'accessToken': store.state.authStore.user.accessToken,
        'fullState': forceFull || store.state.roomStore.rooms == null,
        'since': forceFull ? null : since ?? store.state.roomStore.lastSince,
        'timeout': 10000
      });

      if (data['errcode'] != null) {
        if (data['errcode'] == MatrixErrors.unknown_token) {
          // TODO: signin prompt needed
          print('[fetchSync] invalid token - prompt info on offline mode');
        } else {
          throw data['error'];
        }
      }

      final lastSince = data['next_batch'];
      final oneTimeKeyCount = data['device_one_time_keys_count'];
      final Map<String, dynamic> rawJoined = data['rooms']['join'];
      final Map<String, dynamic> rawInvites = data['rooms']['invite'];
      final Map<String, dynamic> rawLeft = data['rooms']['leave'];
      // TODO:  final Map presence = data['presence'];

      print('[fetchSync] rooms $rawLeft');

      // Local state updates based on changes
      await store.dispatch(syncRooms(rawJoined));
      await store.dispatch(syncRooms(rawInvites));

      // Update encryption one time key count
      store.dispatch(updateOneTimeKeyCounts(oneTimeKeyCount));

      if (isFullSync) {
        store.dispatch(saveSync(data));
      }

      // Update synced to indicate init sync and next batch id (lastSince)
      store.dispatch(SetSynced(
        synced: true,
        syncing: false,
        lastSince: lastSince,
        backoff: null,
      ));

      if (!kReleaseMode && isFullSync) {
        print('[fetchSync] full sync completed');
      }
    } catch (error) {
      final message = (error.message as String);

      if (message.contains('SocketException')) {
        print('[fetchSync] IOException $error');
        store.dispatch(SetOffline(offline: true));
      }

      final backoff = store.state.syncStore.backoff;
      final nextBackoff = backoff != null ? backoff + 1 : 5;
      store.dispatch(SetBackoff(backoff: nextBackoff));
    } finally {
      store.dispatch(SetSyncing(syncing: false));
    }
  };
}

/**
 * Save Cold Storage Data
 * 
 * 
    // Refreshing myself on list concat in dart without spread
    // Map testing = {
    //   "1": ["a", "b", "c"]
    // };
    // Map again = {
    //   "1": ["e", "f", "g"],
    // };

    // testing.update("1", (value) => value + again["1"]);
    // print(testing);
    
 * Will update the cold storage block of data
 * from the full_state /sync call
 */
ThunkAction<AppState> saveSync(
  Map syncData,
) {
  return (Store<AppState> store) async {
    // Offload the full state save
    Cache.sync.close();
    final storageLocation = await initStorageLocation();

    print('[saveSync] started $storageLocation');

    compute(saveSyncIsolate, {
      'location': storageLocation,
      'sync': syncData,
    });

    print('[saveSync] completed');

    Cache.sync = await openHiveSync();
  };
}

/**
 * Load Cold Storage Data
 * 
 * Will update the cold storage block of data
 * from the full_state /sync call
 */
ThunkAction<AppState> loadSync() {
  return (Store<AppState> store) async {
    print('[loadSync] started');
    final storageLocation = await initStorageLocation();

    final syncData = await compute(loadSyncIsolate, {
      'location': storageLocation,
    });

    print('[loadSync] $syncData');
  };
}

// WARNING: ONLY FOR TESTING OUTPUT
Future<String> get _localPath async {
  final directory = await getApplicationDocumentsDirectory();

  return directory.path;
}

// WARNING: ONLY FOR TESTING OUTPUT
Future<File> get _localFile async {
  final path = await _localPath;
  return File('$path/matrix.json');
}

// WARNING: ONLY FOR TESTING OUTPUT
Future<dynamic> readFullSyncJson() async {
  try {
    final file = await _localFile;
    String contents = await file.readAsString();
    return await jsonDecode(contents);
  } catch (error) {
    // If encountering an error, return 0.
    print('readFullSyncJson $error');
    return null;
  } finally {
    print('** Read State From Disk Successfully **');
  }
}
