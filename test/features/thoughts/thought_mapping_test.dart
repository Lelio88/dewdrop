import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:dewdrop/src/features/thoughts/data/thought_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bob = Profile.fromMap({'id': 's1', 'handle': 'bob'});

  Map<String, dynamic> row(
    String id,
    String sender, {
    required bool anon,
    Object? createdAt = '2026-06-16T10:00:00.000Z',
  }) => {
    'id': id,
    'sender_id': sender,
    'is_anonymous': anon,
    'created_at': createdAt,
  };

  test('a named thought keeps its sender', () {
    final out = mapReceivedThoughts(
      [row('t1', 's1', anon: false)],
      {'s1': bob},
    );
    expect(out.single.isAnonymous, false);
    expect(out.single.sender, bob);
  });

  test('an anonymous thought NEVER exposes its sender (privacy)', () {
    // Even if the sender profile is (wrongly) present in the map, anonymity wins.
    final out = mapReceivedThoughts([row('t1', 's1', anon: true)], {'s1': bob});
    expect(out.single.isAnonymous, true);
    expect(out.single.sender, isNull);
  });

  test('masking is strict: only is_anonymous == true masks', () {
    final out = mapReceivedThoughts(
      [
        {
          'id': 't1',
          'sender_id': 's1',
          'created_at': '2026-06-16T10:00:00Z',
        }, // absent
        {
          'id': 't2',
          'sender_id': 's1',
          'is_anonymous': false,
          'created_at': '2026-06-16T10:00:00Z',
        },
      ],
      {'s1': bob},
    );
    expect(out.every((t) => !t.isAnonymous), true);
    expect(out.every((t) => t.sender == bob), true);
  });

  test('a missing sender profile yields a null sender (no crash)', () {
    final out = mapReceivedThoughts([row('t1', 'unknown', anon: false)], {});
    expect(out.single.sender, isNull);
  });

  test('a malformed created_at falls back instead of throwing', () {
    final out = mapReceivedThoughts(
      [row('t1', 's1', anon: false, createdAt: null)],
      {'s1': bob},
    );
    expect(
      out.single.createdAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });

  test('preserves row order', () {
    final out = mapReceivedThoughts(
      [
        row('a', 's1', anon: false),
        row('b', 's1', anon: true),
        row('c', 's1', anon: false),
      ],
      {'s1': bob},
    );
    expect(out.map((t) => t.id), ['a', 'b', 'c']);
  });
}
