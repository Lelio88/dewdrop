import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/common/decor_choice.dart';
import 'package:dewdrop/src/common/seasonal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('activeSeasonalEvent — le jour pile', () {
    test('Halloween is active on 31/10 only', () {
      expect(activeSeasonalEvent(DateTime(2026, 10, 31))?.id, 'halloween');
      expect(activeSeasonalEvent(DateTime(2026, 10, 30)), isNull);
      expect(activeSeasonalEvent(DateTime(2026, 11, 1)), isNull);
    });

    test('1er avril is active on 01/04 only', () {
      expect(activeSeasonalEvent(DateTime(2026, 4, 1))?.id, 'aprilfool');
      expect(activeSeasonalEvent(DateTime(2026, 3, 31)), isNull);
      expect(activeSeasonalEvent(DateTime(2026, 4, 2)), isNull);
    });

    test('Noël spans 24–25/12 inclusive', () {
      expect(activeSeasonalEvent(DateTime(2026, 12, 24))?.id, 'christmas');
      expect(activeSeasonalEvent(DateTime(2026, 12, 25))?.id, 'christmas');
      expect(activeSeasonalEvent(DateTime(2026, 12, 23)), isNull);
      expect(activeSeasonalEvent(DateTime(2026, 12, 26)), isNull);
    });

    test('an ordinary day has no marronnier', () {
      expect(activeSeasonalEvent(DateTime(2026, 6, 15)), isNull);
      expect(activeSeasonalEvent(DateTime(2026, 1, 1)), isNull);
    });

    test('the time of day within an active day does not matter', () {
      expect(
        activeSeasonalEvent(DateTime(2026, 10, 31, 23, 59, 59))?.id,
        'halloween',
      );
      expect(
        activeSeasonalEvent(DateTime(2026, 10, 31, 0, 0, 0))?.id,
        'halloween',
      );
    });
  });

  group('SeasonalEvent', () {
    test('the forced decor strings parse to a real environment', () {
      for (final e in kSeasonalEvents) {
        // parseDecor never throws (falls back to space/0); assert the stub
        // points at a variant the environment actually has.
        final (env, variant) = parseDecor(e.decor);
        expect(
          variant,
          inInclusiveRange(0, env.variantCount - 1),
          reason: '${e.id} → ${e.decor}',
        );
      }
    });

    test('day() sets an inclusive single-day window', () {
      const e = SeasonalEvent.day(
        id: 't',
        label: 't',
        emoji: '⭐',
        month: 5,
        day: 9,
        decor: 'space:0',
        mode: RenderMode.photo,
      );
      expect(e.isActiveOn(DateTime(2026, 5, 9)), isTrue);
      expect(e.isActiveOn(DateTime(2026, 5, 8)), isFalse);
      expect(e.isActiveOn(DateTime(2026, 5, 10)), isFalse);
    });

    test('a year-wrapping window stays active across 31/12 → 01/01', () {
      const nye = SeasonalEvent(
        id: 'nye',
        label: 'nye',
        emoji: '🎆',
        startMonth: 12,
        startDay: 31,
        endMonth: 1,
        endDay: 1,
        decor: 'space:0',
        mode: RenderMode.photo,
      );
      expect(nye.isActiveOn(DateTime(2026, 12, 31)), isTrue);
      expect(nye.isActiveOn(DateTime(2027, 1, 1)), isTrue);
      expect(nye.isActiveOn(DateTime(2026, 12, 30)), isFalse);
      expect(nye.isActiveOn(DateTime(2027, 1, 2)), isFalse);
    });
  });
}
