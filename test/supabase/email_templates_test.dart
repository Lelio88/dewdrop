import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the "every auth email is in French" promise.
///
/// GoTrue silently falls back to its own ENGLISH gabarit for any template a
/// project doesn't override — which is how a French user ended up with an
/// English email even though `confirmation` and `recovery` had been translated.
/// This test fails the moment a template is missing, points at a file that
/// isn't there, or ships something that doesn't look French.
///
/// It reads the repo's own files (tests run from the package root), so it costs
/// nothing and needs no Supabase instance.

/// Every email GoTrue can send. Extend this ONLY together with the matching
/// template — that's the whole point of the list.
const _mustBeOverridden = {
  'confirmation',
  'recovery',
  'email_change',
  'magic_link',
  'reauthentication',
  'invite',
};

/// `[auth.email.template.<name>]` → its `content_path`, read off config.toml.
Map<String, String> _declaredTemplates(String toml) {
  final section = RegExp(r'^\s*\[([^\]]+)\]\s*$');
  final contentPath = RegExp(r'''^\s*content_path\s*=\s*["']([^"']+)["']''');
  final out = <String, String>{};
  String? current;
  for (final line in toml.split('\n')) {
    final head = section.firstMatch(line);
    if (head != null) {
      final name = head.group(1)!;
      current = name.startsWith('auth.email.template.')
          ? name.substring('auth.email.template.'.length)
          : null;
      continue;
    }
    if (current == null) continue;
    final path = contentPath.firstMatch(line);
    if (path != null) out[current] = path.group(1)!;
  }
  return out;
}

void main() {
  final toml = File('supabase/config.toml').readAsStringSync();
  final templates = _declaredTemplates(toml);

  test(
    'every auth email GoTrue can send has a template (no English fallback)',
    () {
      expect(templates.keys, containsAll(_mustBeOverridden));
    },
  );

  for (final name in _mustBeOverridden) {
    group('template "$name"', () {
      test('its content_path points at a file that exists', () {
        final path = templates[name];
        expect(path, isNotNull, reason: '$name has no content_path');
        expect(
          File(path!.replaceFirst('./', '')).existsSync(),
          isTrue,
          reason: '$name declares $path, which is missing',
        );
      });

      test('is written in French', () {
        final html = File(
          templates[name]!.replaceFirst('./', ''),
        ).readAsStringSync();
        expect(html, contains('lang="fr"'));
        // A French body carries accents; an English fallback pasted in wouldn't.
        expect(html, matches(RegExp('[àâçéèêëîïôûù]')));
      });

      test('carries the substitution the flow needs', () {
        final html = File(
          templates[name]!.replaceFirst('./', ''),
        ).readAsStringSync();
        // Reauthentication mails a 6-digit code, every other flow a link.
        // Getting this wrong ships a mail the user cannot act on.
        expect(
          html,
          contains(
            name == 'reauthentication'
                ? '{{ .Token }}'
                : '{{ .ConfirmationURL }}',
          ),
        );
      });
    });
  }

  test('each template declares a subject mentioning DewDrop', () {
    // The subjects are what makes every app email filterable in one rule.
    final subjects = RegExp(
      r'''^\s*subject\s*=\s*["']([^"']+)["']''',
      multiLine: true,
    ).allMatches(toml).map((m) => m.group(1)!).toList();
    expect(subjects, isNotEmpty);
    for (final s in subjects) {
      expect(s, contains('DewDrop'), reason: 'subject "$s" is unbranded');
    }
  });
}
