import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sentence shown for a received pensée. A group pensée that reads like a
/// personal one is the bug this whole file exists to prevent — the recipient
/// could not tell WHICH circle (or whether it was a circle at all).
void main() {
  final lazare = Profile.fromMap({
    'id': 's1',
    'handle': 'lazare',
    'display_name': 'Lazare',
  });
  final noName = Profile.fromMap({'id': 's2', 'handle': 'bob'});

  ReceivedThought thought({
    Profile? sender,
    bool anon = false,
    String? groupId,
    String? groupName,
  }) => ReceivedThought(
    id: 't1',
    createdAt: DateTime(2026),
    isAnonymous: anon,
    sender: sender,
    groupId: groupId,
    groupName: groupName,
  );

  group('thoughtLine', () {
    test('a personal pensée keeps the historic wording', () {
      expect(thoughtLine(thought(sender: lazare)), 'Lazare a pensé à toi');
    });

    test('a group pensée names the group', () {
      final line = thoughtLine(
        thought(sender: lazare, groupId: 'g1', groupName: 'Famille'),
      );
      expect(line, 'Lazare a pensé au groupe « Famille »');
    });

    test('a group whose name no longer resolves says so, not "à toi"', () {
      // We left the group since: RLS hides its name. Saying "a pensé à toi"
      // here would pass a group pensée off as a personal one.
      final line = thoughtLine(thought(sender: lazare, groupId: 'g1'));
      expect(line, 'Lazare a pensé à un groupe');
    });

    test('an empty group name is treated as unresolved', () {
      final line = thoughtLine(
        thought(sender: lazare, groupId: 'g1', groupName: ''),
      );
      expect(line, 'Lazare a pensé à un groupe');
    });

    test('an anonymous group pensée hides the sender, not the group', () {
      final line = thoughtLine(
        thought(anon: true, groupId: 'g1', groupName: 'Famille'),
      );
      expect(line, "Quelqu'un a pensé au groupe « Famille »");
    });

    test('a sender without a display name falls back to the @handle', () {
      expect(thoughtLine(thought(sender: noName)), '@bob a pensé à toi');
    });

    test('an unresolved sender never breaks the line', () {
      expect(thoughtLine(thought()), '@? a pensé à toi');
    });
  });

  group('senderLabel', () {
    test('anonymity wins over any profile still attached', () {
      expect(senderLabel(thought(sender: lazare, anon: true)), "Quelqu'un");
    });

    test('display name wins over handle', () {
      expect(senderLabel(thought(sender: lazare)), 'Lazare');
    });
  });

  test('isGroup follows groupId, not the resolved name', () {
    expect(thought(groupId: 'g1').isGroup, isTrue);
    expect(thought().isGroup, isFalse);
  });
}
