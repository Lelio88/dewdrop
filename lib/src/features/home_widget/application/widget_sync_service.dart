import 'package:dewdrop/src/features/friends/domain/friend.dart';
import 'package:dewdrop/src/features/home_widget/domain/widget_gateway.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';

/// Max friend circles the phase-(a) widget renders (one row of fixed slots).
const int kWidgetSlotCount = 4;

/// Pushes the data the home-screen widget needs to the native side.
///
/// What it does: takes the (already source-ordered) friend list + the user's
/// anonymity default + whether a session exists, writes one record per slot
/// (id/initial/label) plus the global flags, then asks the widget to redraw.
/// The first [kWidgetSlotCount] friends are shown. Ordering is resolved upstream
/// by `widgetSlotFriendsProvider` (auto = most recently contacted, custom = the
/// pinned list) — this service just renders whatever ordered list it's handed.
///
/// Invariant: the per-slot keys and the `anonymous`/`signed_in`/`slot_count`
/// flags MUST stay byte-identical to what `DewDropWidgetProvider.kt` reads and
/// what the background send isolate consults — they are one contract.
///
/// Usage: `await widgetSyncService.push(friends: friends, anonymous: a, signedIn: s)`.
class WidgetSyncService {
  const WidgetSyncService(this._gateway);

  final WidgetGateway _gateway;

  Future<void> push({
    required List<Friend> friends,
    required bool anonymous,
    required bool signedIn,
  }) async {
    final shown = friends.take(kWidgetSlotCount).toList();

    await _gateway.saveBool('signed_in', signedIn);
    await _gateway.saveBool('anonymous', anonymous);
    await _gateway.saveInt('slot_count', shown.length);

    for (var i = 0; i < kWidgetSlotCount; i++) {
      if (i < shown.length) {
        final p = shown[i].profile;
        await _gateway.saveString('slot${i}_id', p.id);
        await _gateway.saveString('slot${i}_initial', _initial(p));
        await _gateway.saveString('slot${i}_label', _label(p));
      } else {
        // Clear stale slots so a shrinking friend list doesn't leave ghosts.
        await _gateway.saveString('slot${i}_id', '');
        await _gateway.saveString('slot${i}_initial', '');
        await _gateway.saveString('slot${i}_label', '');
      }
    }

    await _gateway.refresh();
  }

  /// Mirrors `SendDock._name`: display name when set, else the @handle.
  String _label(Profile p) =>
      p.displayName?.isNotEmpty == true ? p.displayName! : '@${p.handle}';

  /// Mirrors `SendDock._initial`: first letter of the label, '@' stripped.
  String _initial(Profile p) {
    final s = _label(p);
    return s.isEmpty ? '?' : s.replaceAll('@', '')[0].toUpperCase();
  }
}
