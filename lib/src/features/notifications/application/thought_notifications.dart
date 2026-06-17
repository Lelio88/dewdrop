import 'dart:convert';
import 'dart:ui' show Color;

import 'package:dewdrop/src/features/notifications/application/notification_channels.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the **grouped** "pensée" notifications from FCM **data** messages,
/// usable from BOTH the foreground and the background isolate.
///
/// Model (what the user asked for):
///  - a single **"DewDrop"** group in the tray (`_groupKey`),
///  - **one child per sender/group** (notification id = a stable hash of the
///    sender key, so repeated pensées from the same person UPDATE one child,
///    "X · N pensées", instead of stacking),
///  - **sound/vibration once**: only the summary alerts
///    ([GroupAlertBehavior.summary]) and it's `onlyAlertOnce`, so it rings on the
///    first post and stays quiet on updates — until the app is opened (we
///    [clearThoughtNotifications]) or the user clears the tray (a fresh post
///    then rings again). During quiet hours the silent channel is used instead.
///
/// State (per-sender counts) lives in [SharedPreferences] under [_stateKey] so it
/// survives across data messages and is reachable from the background isolate.

const String _groupKey = 'dewdrop_thoughts';
const String _stateKey = 'notif_thoughts';
const int _summaryId = 0; // reserved; child ids are non-zero hashes

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
bool _initialized = false;

Future<void> _ensureInit() async {
  if (_initialized) return;
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_dewdrop'),
    ),
  );
  _initialized = true;
}

/// Handle one incoming pensée data message: bump the sender's count and
/// (re)build that sender's child + the "DewDrop" summary. No-op for other types.
Future<void> showThoughtNotification(RemoteMessage message) async {
  final data = message.data;
  if (data['type'] != 'thought') return;

  final senderKey = data['sender_key'] ?? 'unknown';
  final label = data['label']?.isNotEmpty == true ? data['label']! : 'Quelqu\'un';
  final body = data['message']?.isNotEmpty == true
      ? data['message']!
      : 'a pensé à toi';
  final silent = data['silent'] == '1';

  await _ensureInit();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // pick up writes from the other isolate
  final state = _loadState(prefs);
  final count = ((state[senderKey] as int?) ?? 0) + 1;
  state[senderKey] = count;
  await prefs.setString(_stateKey, jsonEncode(state));

  var total = 0;
  for (final v in state.values) {
    total += (v as int?) ?? 0;
  }

  // One child per sender (updates in place via the stable id).
  await _plugin.show(
    id: _idFor(senderKey),
    title: label,
    body: count == 1 ? body : '$count pensées 💭',
    notificationDetails: NotificationDetails(
      android: _android(silent: silent, summary: false),
    ),
  );

  // The group summary — the only one that alerts (once).
  await _plugin.show(
    id: _summaryId,
    title: 'DewDrop',
    body: total <= 1 ? '1 pensée 💭' : '$total pensées 💭',
    notificationDetails: NotificationDetails(
      android: _android(silent: silent, summary: true),
    ),
  );
}

/// Called when the app is opened/resumed: the pensées are now seen, so clear the
/// whole "DewDrop" group and reset the counters (re-arms the alert).
Future<void> clearThoughtNotifications() async {
  await _ensureInit();
  await _plugin.cancelAll();
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_stateKey);
}

Map<String, dynamic> _loadState(SharedPreferences prefs) {
  final raw = prefs.getString(_stateKey);
  if (raw == null) return {};
  try {
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  } on FormatException {
    return {};
  }
}

// Stable, positive id per sender; never 0 (reserved for the summary).
int _idFor(String key) {
  final h = key.hashCode & 0x7fffffff;
  return h == _summaryId ? 1 : h;
}

AndroidNotificationDetails _android({
  required bool silent,
  required bool summary,
}) {
  return AndroidNotificationDetails(
    silent ? thoughtsSilentChannelId : thoughtsChannelId,
    silent ? 'Pensées (silencieux)' : 'Pensées',
    channelDescription: 'Quand un ami pense à toi',
    importance: silent ? Importance.low : Importance.high,
    priority: silent ? Priority.low : Priority.high,
    icon: 'ic_stat_dewdrop',
    color: const Color(0xFF8FB7FF),
    groupKey: _groupKey,
    setAsGroupSummary: summary,
    // Only the summary makes a sound, and only once until the group is cleared.
    onlyAlertOnce: true,
    groupAlertBehavior: GroupAlertBehavior.summary,
  );
}
