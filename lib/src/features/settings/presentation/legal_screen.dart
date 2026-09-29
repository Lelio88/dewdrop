import 'package:dewdrop/src/common/legal_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// « Informations légales » — reachable from « À propos & crédits ».
///
/// A short, plain-words summary, then links that open the hosted pages
/// (privacy policy, terms, legal notice) in the browser. The full texts live
/// only in `docs/` (see [LegalLinks]): the app never carries a second copy
/// that could drift from the page Google Play links to. The summary must stay
/// true to those pages — change it in the same commit as they do.
class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key});

  static const String _summary =
      'DewDrop garde le minimum pour fonctionner : ton email, ton @handle et '
      'ton pseudo, tes amis, tes cercles, les pensées échangées et tes '
      'réglages. Ni publicité, ni revente, ni pistage.\n\n'
      'Les données sont hébergées dans l\'Union européenne (Supabase, Irlande). '
      'Les notifications et les rapports de plantage passent par Google '
      'Firebase ; tu peux couper ces rapports dans Réglages.\n\n'
      'Supprimer ton compte efface tout, tout de suite : Réglages → Supprimer '
      'mon compte.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = Colors.white;
    Future<void> open(Uri uri) async {
      final ok = await ref.read(externalLinkOpenerProvider)(uri);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir le lien.")),
        );
      }
    }

    Widget link(String title, String subtitle, Uri uri) => Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: TextStyle(color: w)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: w.withValues(alpha: 0.5)),
        ),
        trailing: Icon(
          Icons.open_in_new,
          color: w.withValues(alpha: 0.4),
          semanticLabel: 'Ouvre le navigateur',
        ),
        onTap: () => open(uri),
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Informations légales'),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'En bref',
                style: TextStyle(
                  color: w,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _summary,
                style: TextStyle(color: w.withValues(alpha: 0.72), height: 1.5),
              ),
              const SizedBox(height: 24),
              link(
                'Politique de confidentialité',
                'Données, durées, sous-traitants, tes droits',
                LegalLinks.privacy,
              ),
              Divider(color: w.withValues(alpha: 0.08), height: 1),
              link(
                "Conditions d'utilisation",
                'Les règles du service',
                LegalLinks.terms,
              ),
              Divider(color: w.withValues(alpha: 0.08), height: 1),
              link(
                'Mentions légales',
                'Éditeur et hébergeur',
                LegalLinks.legalNotice,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
