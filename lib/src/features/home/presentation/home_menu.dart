import 'dart:ui';

import 'package:dewdrop/src/features/auth/application/auth_providers.dart';
import 'package:dewdrop/src/features/notifications/application/push_providers.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/settings/application/seasonal_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The home's ☰ sheet: identity header, then every destination the gestures
/// also reach. It exists because a gesture is not discoverable — anyone who
/// never finds the swipes must still be able to use the whole app from here.
///
/// Pops a string result the home turns into a route (or the decor picker);
/// sign-out is handled inline, since it must drop the push token while the
/// session is still valid.
class HomeMenu extends ConsumerWidget {
  const HomeMenu({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final white = Colors.white;
    final seasonal = ref.watch(seasonalOverrideProvider);
    final media = MediaQuery.of(context);
    // viewPadding (not padding): the inset survives even when the nav bar is
    // hidden by immersive mode, so the bottom items stay above where it sits.
    final bottom = media.viewPadding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          // Cap the height + scroll, so a small screen never pushes the last
          // items ("Réglages" / "Se déconnecter") off the bottom.
          constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
          padding: EdgeInsets.fromLTRB(22, 14, 22, 18 + bottom),
          decoration: BoxDecoration(
            color: white.withValues(alpha: 0.10),
            border: Border.all(color: white.withValues(alpha: 0.18)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Centered identity header — app name, then name + handle, no avatar.
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'DewDrop',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 2,
                          color: white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (profile.displayName?.isNotEmpty == true) ...[
                        Text(
                          profile.displayName!,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${profile.handle}',
                          style: TextStyle(
                            color: white.withValues(alpha: 0.55),
                          ),
                        ),
                      ] else
                        Text(
                          '@${profile.handle}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: white,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Divider(color: white.withValues(alpha: 0.15), height: 1),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.send_rounded,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Envoyer une pensée'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('send'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.auto_awesome_outlined,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Pensées reçues'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('thoughts'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.group_outlined,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Amis'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('friends'),
                ),
                // Univers — locked shut while a marronnier owns the screen; the
                // user's own world returns on its own once the window closes.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: seasonal == null,
                  leading: Icon(
                    Icons.palette_outlined,
                    color: white.withValues(
                      alpha: seasonal == null ? 0.85 : 0.4,
                    ),
                  ),
                  title: const Text('Univers'),
                  subtitle: seasonal == null
                      ? null
                      : Text(
                          '${seasonal.emoji} ${seasonal.label} — verrouillé pour aujourd’hui',
                          style: TextStyle(
                            color: white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                  trailing: Icon(
                    seasonal == null
                        ? Icons.chevron_right
                        : Icons.lock_outline_rounded,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: seasonal == null
                      ? () => Navigator.of(context).pop('decor')
                      : null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.tune_rounded,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Réglages'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: white.withValues(alpha: 0.5),
                  ),
                  onTap: () => Navigator.of(context).pop('settings'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.logout_rounded,
                    color: white.withValues(alpha: 0.85),
                  ),
                  title: const Text('Se déconnecter'),
                  onTap: () async {
                    // Capture before popping — the sheet's `ref` is gone after pop.
                    final push = ref.read(pushServiceProvider);
                    final auth = ref.read(authRepositoryProvider);
                    Navigator.of(context).pop();
                    try {
                      // Drop the device token while still authenticated (RLS),
                      // then sign out. Best-effort: a failure must not strand the
                      // user in a half-signed-out state silently.
                      await push.unregister();
                      await auth.signOut();
                    } on Exception catch (_) {
                      // The router redirect handles navigation on success.
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
