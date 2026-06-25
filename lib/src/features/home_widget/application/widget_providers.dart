import 'package:dewdrop/src/features/friends/application/friend_providers.dart';
import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/home_widget/application/widget_sync_service.dart';
import 'package:dewdrop/src/features/home_widget/data/home_widget_gateway.dart';
import 'package:dewdrop/src/features/home_widget/domain/widget_gateway.dart';
import 'package:dewdrop/src/features/profile/application/profile_providers.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Platform widget gateway. Concrete `home_widget` impl wired here (this
/// project keeps the impl in the application provider, like `friend_providers`).
final widgetGatewayProvider = Provider<WidgetGateway>((ref) {
  return const HomeWidgetGateway();
});

/// Service that pushes the friend slots to the home-screen widget.
final widgetSyncServiceProvider = Provider<WidgetSyncService>((ref) {
  return WidgetSyncService(ref.watch(widgetGatewayProvider));
});

/// The friends to render in the home-screen widget, already ordered by the
/// user's chosen source:
///   'auto'   → most recently contacted first, then the remaining friends;
///   'custom' → the pinned [Profile.widgetFriends] list, in its saved order.
///
/// Truncation to [kWidgetSlotCount] happens in [WidgetSyncService]. Falls back
/// to the default friend order when a custom selection is empty or fully stale
/// (all pinned friends removed), so a leftover config never blanks the widget.
final widgetSlotFriendsProvider = Provider<List<Friend>>((ref) {
  final friends = ref.watch(friendsProvider).value ?? const <Friend>[];
  if (friends.isEmpty) return const <Friend>[];

  final profile = ref.watch(myProfileProvider).value;
  final byId = {for (final f in friends) f.profile.id: f};

  if (profile?.widgetSource == 'custom') {
    final ordered = <Friend>[];
    for (final id in profile!.widgetFriends) {
      final f = byId[id];
      if (f != null) ordered.add(f);
    }
    return ordered.isNotEmpty ? ordered : friends;
  }

  // 'auto' (default): recently contacted first, then the rest, deduped.
  final recent = ref.watch(recentContactsProvider).value ?? const <String>[];
  final seen = <String>{};
  final ordered = <Friend>[];
  for (final id in recent) {
    final f = byId[id];
    if (f != null && seen.add(id)) ordered.add(f);
  }
  for (final f in friends) {
    if (seen.add(f.profile.id)) ordered.add(f);
  }
  return ordered;
});
