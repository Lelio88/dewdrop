import 'package:dewdrop/src/common/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeepLinks.invite', () {
    test('builds an HTTPS, clickable invite link for a handle', () {
      expect(
        DeepLinks.invite('alice'),
        'https://dewdrop.heianenterprise.com/invite.html?handle=alice',
      );
    });

    test('inviteScheme builds the custom-scheme hand-off link', () {
      expect(DeepLinks.inviteScheme('alice'), 'dewdrop://invite?handle=alice');
    });
  });

  group('DeepLinks.inviteHandle', () {
    test('extracts the handle from the HTTPS web link', () {
      final uri = Uri.parse(DeepLinks.invite('alice'));
      expect(DeepLinks.inviteHandle(uri), 'alice');
    });

    test('extracts the handle from the custom-scheme link', () {
      final uri = Uri.parse('dewdrop://invite?handle=alice');
      expect(DeepLinks.inviteHandle(uri), 'alice');
    });

    test('strips a leading @ from the handle', () {
      final uri = Uri.parse('dewdrop://invite?handle=@bob');
      expect(DeepLinks.inviteHandle(uri), 'bob');
    });

    test('round-trips with invite()', () {
      final uri = Uri.parse(DeepLinks.invite('carol'));
      expect(DeepLinks.inviteHandle(uri), 'carol');
    });

    test('returns null for an auth callback link (left to Supabase)', () {
      expect(
        DeepLinks.inviteHandle(Uri.parse(DeepLinks.loginCallback)),
        isNull,
      );
      expect(
        DeepLinks.inviteHandle(Uri.parse(DeepLinks.resetPassword)),
        isNull,
      );
    });

    test('still reads invite links and QR codes shared before the move', () {
      final uri = Uri.parse(
        'https://lelio88.github.io/dewdrop/invite.html?handle=dave',
      );
      expect(DeepLinks.inviteHandle(uri), 'dave');
    });

    test('ignores another site on the old shared GitHub host', () {
      final uri = Uri.parse(
        'https://lelio88.github.io/GTG/invite.html?handle=alice',
      );
      expect(DeepLinks.inviteHandle(uri), isNull);
    });

    test('returns null for an HTTPS link on a foreign host', () {
      final uri = Uri.parse(
        'https://evil.example/dewdrop/invite.html?handle=alice',
      );
      expect(DeepLinks.inviteHandle(uri), isNull);
    });

    test('returns null for a foreign scheme', () {
      final uri = Uri.parse('ftp://invite?handle=alice');
      expect(DeepLinks.inviteHandle(uri), isNull);
    });

    test('returns null when the handle is missing or empty', () {
      expect(DeepLinks.inviteHandle(Uri.parse('dewdrop://invite')), isNull);
      expect(
        DeepLinks.inviteHandle(Uri.parse('dewdrop://invite?handle=')),
        isNull,
      );
    });
  });

  group('DeepLinks.sendTo / sendTarget', () {
    test('sendTo builds the custom-scheme send link', () {
      expect(DeepLinks.sendTo('alice'), 'dewdrop://send?to=alice');
    });

    test('sendTarget extracts the handle and round-trips with sendTo', () {
      expect(
        DeepLinks.sendTarget(Uri.parse(DeepLinks.sendTo('carol'))),
        'carol',
      );
    });

    test('sendTarget strips a leading @', () {
      expect(DeepLinks.sendTarget(Uri.parse('dewdrop://send?to=@bob')), 'bob');
    });

    test('sendTarget returns null for an invite or auth link', () {
      expect(
        DeepLinks.sendTarget(Uri.parse('dewdrop://invite?handle=al')),
        isNull,
      );
      expect(DeepLinks.sendTarget(Uri.parse(DeepLinks.loginCallback)), isNull);
    });

    test('sendTarget returns null when the target is missing or empty', () {
      expect(DeepLinks.sendTarget(Uri.parse('dewdrop://send')), isNull);
      expect(DeepLinks.sendTarget(Uri.parse('dewdrop://send?to=')), isNull);
    });

    test('inviteHandle ignores a send link (handlers stay disjoint)', () {
      expect(
        DeepLinks.inviteHandle(Uri.parse('dewdrop://send?to=alice')),
        isNull,
      );
    });
  });

  group('liens entre apps (jumeler.html, rejoindre.html)', () {
    test('twinParams lit les paramètres du fragment de jumeler.html', () {
      final uri = Uri.parse(
        'https://dewdrop.heianenterprise.com/jumeler.html'
        '#de=agora&code=ABCD2345&nom=Les+copains&etat=abcdefghijklmnop',
      );
      expect(DeepLinks.twinParams(uri), {
        'de': 'agora',
        'code': 'ABCD2345',
        'nom': 'Les copains',
        'etat': 'abcdefghijklmnop',
      });
    });

    test('twinParams ignore la requête : un code n\'y voyage jamais', () {
      final uri = Uri.parse(
        'https://dewdrop.heianenterprise.com/jumeler.html?de=agora&code=ABCD2345',
      );
      expect(DeepLinks.twinParams(uri), isEmpty);
    });

    test('twinParams refuse un autre hôte, une autre page ou http', () {
      for (final link in [
        'https://evil.example/jumeler.html#de=agora',
        'https://dewdrop.heianenterprise.com/invite.html#de=agora',
        'http://dewdrop.heianenterprise.com/jumeler.html#de=agora',
        'dewdrop://jumeler.html#de=agora',
      ]) {
        expect(DeepLinks.twinParams(Uri.parse(link)), isNull, reason: link);
      }
    });

    test('joinCode lit et valide le code de rejoindre.html', () {
      expect(
        DeepLinks.joinCode(
          Uri.parse(
            DeepLinks.joinPage.replace(fragment: 'code=abcd2345').toString(),
          ),
        ),
        'ABCD2345',
      );
      expect(
        DeepLinks.joinCode(
          Uri.parse(
            'https://dewdrop.heianenterprise.com/rejoindre.html#code=ABC',
          ),
        ),
        isNull,
      );
      expect(
        DeepLinks.joinCode(
          Uri.parse(
            'https://dewdrop.heianenterprise.com/rejoindre.html?code=ABCD2345',
          ),
        ),
        isNull,
      );
    });

    test('les liens entre apps ne sont ni une invitation ni un envoi', () {
      final uri = Uri.parse(
        'https://dewdrop.heianenterprise.com/rejoindre.html#code=ABCD2345',
      );
      expect(DeepLinks.inviteHandle(uri), isNull);
      expect(DeepLinks.sendTarget(uri), isNull);
      expect(DeepLinks.twinParams(uri), isNull);
    });
  });
}
