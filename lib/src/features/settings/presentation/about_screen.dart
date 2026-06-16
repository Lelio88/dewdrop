import 'package:flutter/material.dart';

/// "À propos & crédits" — surfaces the notices legally required to publish on the
/// app stores, in-app and visible to users:
///
///  • **Audio attribution** for the one CC BY asset shipped (the desert
///    tumbleweed). CC BY 4.0 requires the credit to be *visible to users* — a
///    repo `CREDITS.md` alone is not sufficient. Every other shipped sound is
///    CC0 / public domain (no attribution owed); they're thanked for
///    transparency only.
///  • **Open-source licenses** via Flutter's built-in [showLicensePage], which
///    aggregates every bundled package's `LICENSE` file — this is how the
///    MIT/BSD/Apache notice obligations of the dependency tree are satisfied.
///
/// Reached from Réglages → « À propos & crédits ». Pure presentation: the legal
/// text is static, so there is no domain/application layer behind it.
///
/// Invariant: if a new attribution-requiring asset (CC BY / CC BY-SA) is ever
/// shipped, it MUST be added to the "Crédits audio" section here, not only to
/// `CREDITS.md`.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  /// Keep in sync with `version:` in `pubspec.yaml`.
  static const String _appVersion = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final w = Colors.white;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('À propos & crédits'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12162A), Color(0xFF06070E)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              _section(w, 'DewDrop'),
              _card(
                w,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Envoie une pensée à un ami.',
                          style: TextStyle(color: w, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('Version $_appVersion',
                          style: TextStyle(color: w.withValues(alpha: 0.5))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _section(w, 'Crédits audio'),
              _card(
                w,
                child: _credit(
                  w,
                  title: 'Virevoltant du désert',
                  body: '« Tumbleweed_Impact » par duckduckpony — Freesound.\n'
                      'Licence CC BY 4.0 (modifié).',
                  links: const [
                    'freesound.org/s/204028',
                    'freesound.org/s/204031',
                    'creativecommons.org/licenses/by/4.0',
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                w,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Toutes les autres ambiances, musiques, sons ponctuels et le '
                    'son de notification sont en CC0 1.0 / domaine public '
                    '(Freesound, OpenGameArt, NOAA) — aucune attribution requise. '
                    'Merci à leurs auteurs.',
                    style: TextStyle(
                        color: w.withValues(alpha: 0.55), height: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _section(w, 'Logiciel'),
              _card(
                w,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Licences open source',
                      style: TextStyle(color: w)),
                  subtitle: Text('Bibliothèques tierces et leurs licences',
                      style: TextStyle(color: w.withValues(alpha: 0.5))),
                  trailing: Icon(Icons.chevron_right,
                      color: w.withValues(alpha: 0.4)),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'DewDrop',
                    applicationVersion: _appVersion,
                    applicationLegalese: '© 2026 DewDrop',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _credit(
    Color w, {
    required String title,
    required String body,
    required List<String> links,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(color: w, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(body,
                style:
                    TextStyle(color: w.withValues(alpha: 0.7), height: 1.4)),
            const SizedBox(height: 6),
            for (final l in links)
              SelectableText(l,
                  style: TextStyle(
                      color: w.withValues(alpha: 0.5),
                      fontSize: 12.5,
                      height: 1.5)),
          ],
        ),
      );

  Widget _section(Color w, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: w.withValues(alpha: 0.6))),
      );

  Widget _card(Color w, {required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: w.withValues(alpha: 0.06),
          border: Border.all(color: w.withValues(alpha: 0.12)),
        ),
        child: child,
      );
}
