import 'dart:async';

import 'package:dewdrop/src/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoRouterRefreshStream', () {
    test('notifies listeners on each auth event', () async {
      final controller = StreamController<int>();
      final refresh = GoRouterRefreshStream(controller.stream);
      addTearDown(() {
        refresh.dispose();
        controller.close();
      });
      var ticks = 0;
      refresh.addListener(() => ticks++);

      controller.add(1);
      await pumpEventQueue();

      expect(ticks, 1);
    });

    test(
      'swallows stream errors instead of leaking them as uncaught '
      '(an offline token refresh must not surface as a fatal crash)',
      () async {
        final controller = StreamController<int>();
        final uncaught = <Object>[];
        late GoRouterRefreshStream refresh;
        var ticks = 0;

        await runZonedGuarded(() async {
          refresh = GoRouterRefreshStream(controller.stream);
          refresh.addListener(() => ticks++);
          controller.addError(Exception('AuthRetryableFetchException'));
          await pumpEventQueue();
          // The stream keeps flowing after an error.
          controller.add(1);
          await pumpEventQueue();
        }, (error, _) => uncaught.add(error));

        addTearDown(() {
          refresh.dispose();
          controller.close();
        });
        expect(uncaught, isEmpty);
        expect(ticks, 1);
      },
    );
  });
}
