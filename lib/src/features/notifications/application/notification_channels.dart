import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The notification channel for incoming "pensées".
///
/// Its sound is the water drop (`android/app/src/main/res/raw/drop.wav`).
///
/// Invariant: on Android 8+ a channel's sound is **immutable once created** on a
/// device. To change the drop sound later, bump [thoughtsChannelId]
/// (`thoughts_v3`, …) AND add the previous id to [_supersededChannelIds] so a
/// fresh channel is created — editing the WAV alone will not take effect on
/// devices that already created the old channel.
///
/// FCM messages target this channel via `android.notification.channel_id`, and
/// it is also declared as the app's default FCM channel in AndroidManifest.
const String thoughtsChannelId = 'thoughts_v3';

/// Old channel ids to delete on startup so a device that created one of them
/// picks up the current sound (each sound bump appends the retired id here).
const List<String> _supersededChannelIds = ['thoughts_v1', 'thoughts_v2'];

const AndroidNotificationChannel _thoughtsChannel = AndroidNotificationChannel(
  thoughtsChannelId,
  'Pensées',
  description: 'Quand un ami pense à toi',
  importance: Importance.high,
  sound: RawResourceAndroidNotificationSound('drop'),
);

/// Creates the "Pensées" channel (idempotent). Call once at startup, on mobile.
/// No-op on platforms without an Android notifications implementation.
Future<void> ensureThoughtsChannel() async {
  final android = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  // Remove superseded channels (a channel's sound is immutable once created)
  // so the current water-drop sound applies on devices that had an old one.
  for (final id in _supersededChannelIds) {
    await android?.deleteNotificationChannel(channelId: id);
  }
  await android?.createNotificationChannel(_thoughtsChannel);
}
