import 'dart:async';
import 'dart:convert';

import 'package:sembast/sembast.dart';
import 'package:syphon/global/print.dart';
import 'package:syphon/storage/constants.dart';
import 'package:syphon/store/events/ephemeral/m.read/model.dart';

///
/// Save Receipts
///
///
Future<void> saveReceipts(
  Map<String, ReadReceipt>? receipts, {
  Database? storage,
  required bool ready,
}) async {
  final store = StoreRef<String, String>(StorageKeys.RECEIPTS);

  // TODO: the initial sync loads way too many read receipts
  if (!ready) return;

  return storage!.transaction((txn) async {
    for (final key in receipts!.keys) {
      final record = store.record(key);
      await record.put(txn, json.encode(receipts[key]));
    }
  });
}

///
/// Load Receipts
///
/// Iterates through
///
Future<Map<String, ReadReceipt>> loadReceipts(
  List<String?> messageIds, {
  required Database storage,
}) async {
  try {
    final store = StoreRef<String?, String>(StorageKeys.RECEIPTS);

    final receiptsMap = <String, ReadReceipt>{};
    final records = await store.records(messageIds).getSnapshots(storage);

    for (RecordSnapshot<String?, String>? record in records) {
      if (record != null) {
        final receipt = ReadReceipt.fromJson(await json.decode(record.value));
        receiptsMap.putIfAbsent(record.key!, () => receipt);
      }
    }
    return receiptsMap;
  } catch (error) {
    printError(error.toString());
    return {};
  }
}
