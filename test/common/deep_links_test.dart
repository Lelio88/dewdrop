import 'package:dewdrop/src/common/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeepLinks.invite', () {
    test('builds an HTTPS, clickable invite link for a handle', () {
      expect(
        DeepLinks.invite('alice'),
        'https://lelio88.github.io/dewdrop/invite.html?handle=alice',
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
}
