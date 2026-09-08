import 'package:dewdrop/src/features/home_widget/domain/pin_order.dart';
import 'package:flutter_test/flutter_test.dart';

/// `newIndex` follows the `onReorderItem` convention: it is the destination
/// index **in the list once the dragged item has been taken out**. Flutter's
/// ReorderableList already subtracts one for a downward move before calling us
/// (see `widgets/reorderable_list.dart`, `_handleReorderItem`), so these cases
/// are written the way the framework hands them over — no off-by-one here.
void main() {
  const abcde = ['a', 'b', 'c', 'd', 'e'];

  group('reorderPinned', () {
    test('moves an item down to the asked position', () {
      // 'a' dropped between 'c' and 'd' → framework sends (0, 2).
      expect(reorderPinned(abcde, 0, 2), ['b', 'c', 'a', 'd', 'e']);
    });

    test('moves an item up to the asked position', () {
      expect(reorderPinned(abcde, 3, 1), ['a', 'd', 'b', 'c', 'e']);
    });

    test('moves an item to the very end', () {
      expect(reorderPinned(abcde, 1, 4), ['a', 'c', 'd', 'e', 'b']);
    });

    test('moves an item to the very front', () {
      expect(reorderPinned(abcde, 4, 0), ['e', 'a', 'b', 'c', 'd']);
    });

    test('keeps every item, exactly once', () {
      final out = reorderPinned(abcde, 2, 0);
      expect(out.length, abcde.length);
      expect(out.toSet(), abcde.toSet());
    });

    test('leaves the source list untouched', () {
      final source = [...abcde];
      reorderPinned(source, 0, 3);
      expect(source, abcde);
    });

    test('a move onto itself changes nothing', () {
      expect(reorderPinned(abcde, 2, 2), abcde);
    });

    test('handles a two-item swap', () {
      expect(reorderPinned(const ['a', 'b'], 0, 1), ['b', 'a']);
    });
  });
}
