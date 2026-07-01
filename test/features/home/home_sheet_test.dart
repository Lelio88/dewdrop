import 'package:dewdrop/src/features/home/domain/home_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextSheetState', () {
    test('closed + up opens envoyer at peek', () {
      expect(
        nextSheetState(SheetState.closed, up: true),
        const SheetState(HomeSheet.send, SheetStage.peek),
      );
    });

    test('closed + down opens reçus at peek', () {
      expect(
        nextSheetState(SheetState.closed, up: false),
        const SheetState(HomeSheet.recus, SheetStage.peek),
      );
    });

    test('send peek + up escalates to full', () {
      expect(
        nextSheetState(
          const SheetState(HomeSheet.send, SheetStage.peek),
          up: true,
        ),
        const SheetState(HomeSheet.send, SheetStage.full),
      );
    });

    test('send peek + down closes', () {
      expect(
        nextSheetState(
          const SheetState(HomeSheet.send, SheetStage.peek),
          up: false,
        ),
        SheetState.closed,
      );
    });

    test('send full + down retreats to peek (not closed)', () {
      expect(
        nextSheetState(
          const SheetState(HomeSheet.send, SheetStage.full),
          up: false,
        ),
        const SheetState(HomeSheet.send, SheetStage.peek),
      );
    });

    test('send full + up stays full (idempotent)', () {
      expect(
        nextSheetState(
          const SheetState(HomeSheet.send, SheetStage.full),
          up: true,
        ),
        const SheetState(HomeSheet.send, SheetStage.full),
      );
    });

    test('reçus peek + down escalates to full', () {
      expect(
        nextSheetState(
          const SheetState(HomeSheet.recus, SheetStage.peek),
          up: false,
        ),
        const SheetState(HomeSheet.recus, SheetStage.full),
      );
    });

    test('reçus peek + up closes', () {
      expect(
        nextSheetState(
          const SheetState(HomeSheet.recus, SheetStage.peek),
          up: true,
        ),
        SheetState.closed,
      );
    });

    test('reçus full + up retreats to peek (not closed)', () {
      expect(
        nextSheetState(
          const SheetState(HomeSheet.recus, SheetStage.full),
          up: true,
        ),
        const SheetState(HomeSheet.recus, SheetStage.peek),
      );
    });

    test('a full two-stage open then full two-stage close round-trips', () {
      var s = SheetState.closed;
      s = nextSheetState(s, up: true); // → send peek
      s = nextSheetState(s, up: true); // → send full
      expect(s, const SheetState(HomeSheet.send, SheetStage.full));
      s = nextSheetState(s, up: false); // → send peek
      s = nextSheetState(s, up: false); // → closed
      expect(s, SheetState.closed);
    });
  });

  test('SheetState equality + isOpen', () {
    expect(SheetState.closed.isOpen, isFalse);
    expect(const SheetState(HomeSheet.send, SheetStage.peek).isOpen, isTrue);
    expect(
      const SheetState(HomeSheet.send, SheetStage.peek),
      const SheetState(HomeSheet.send, SheetStage.peek),
    );
  });
}
