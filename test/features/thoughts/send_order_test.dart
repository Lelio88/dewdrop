import 'package:dewdrop/src/features/thoughts/domain/send_order.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in for a send target (friend or group).
class _Target {
  const _Target(this.id, this.label);
  final String id;
  final String label;
}

List<String> _order(
  List<_Target> targets,
  List<String> recent,
) => sortByRecency(
  targets,
  idOf: (t) => t.id,
  labelOf: (t) => t.label,
  recentIdsNewestFirst: recent,
).map((t) => t.id).toList();

void main() {
  const alice = _Target('a', 'Alice');
  const bob = _Target('b', 'bob');
  const chloe = _Target('c', 'Chloé');

  group('sortByRecency', () {
    test('puts the most recently contacted first', () {
      expect(
        _order([alice, bob, chloe], ['c', 'a']),
        ['c', 'a', 'b'],
      );
    });

    test('sorts never-contacted entries alphabetically, after contacted ones', () {
      expect(
        _order([chloe, bob, alice], ['c']),
        ['c', 'a', 'b'], // Chloé (recent), then Alice, bob (case-insensitive)
      );
    });

    test('falls back to alphabetical order when nothing was ever sent', () {
      expect(_order([chloe, bob, alice], const []), ['a', 'b', 'c']);
    });

    test('ignores recent ids that are no longer in the list', () {
      expect(_order([alice, bob], ['zz', 'b']), ['b', 'a']);
    });

    test('keeps the first (newest) rank when an id repeats', () {
      // 'a' was contacted last AND earlier — the newest occurrence wins.
      expect(_order([alice, bob], ['a', 'b', 'a']), ['a', 'b']);
    });

    test('is total: identical labels still order deterministically by id', () {
      const dup1 = _Target('x', 'Sam');
      const dup2 = _Target('y', 'Sam');
      expect(_order([dup2, dup1], const []), ['x', 'y']);
    });

    test('does not mutate the input list', () {
      final input = [chloe, alice];
      sortByRecency(
        input,
        idOf: (t) => t.id,
        labelOf: (t) => t.label,
        recentIdsNewestFirst: const ['a'],
      );
      expect(input.map((t) => t.id), ['c', 'a']);
    });
  });
}
