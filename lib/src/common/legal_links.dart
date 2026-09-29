import 'package:dewdrop/src/common/deep_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public legal pages, served by GitHub Pages from `docs/`.
///
/// The app shows no copy of these texts: it opens the hosted pages, so the
/// policy exists in one place and never drifts from what Google Play links to.
///
/// Invariants:
/// - [privacy] is the privacy policy URL declared on the Play listing: moving
///   it means changing the listing the same day.
/// - [accountDeletion] is the web deletion URL Google Play requires for apps
///   with accounts (declared in the « Data safety » form).
/// - Each URL has its page in `docs/`; renaming one breaks the other.
abstract final class LegalLinks {
  static final Uri privacy = Uri.parse('${DeepLinks.webBase}/');
  static final Uri terms = Uri.parse('${DeepLinks.webBase}/cgu.html');
  static final Uri legalNotice = Uri.parse(
    '${DeepLinks.webBase}/mentions-legales.html',
  );
  static final Uri accountDeletion = Uri.parse(
    '${DeepLinks.webBase}/suppression-compte.html',
  );
}

/// Opens a web page outside the app; resolves `false` when nothing could open
/// it. A provider so screens stay testable without a platform browser.
final externalLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  },
);
