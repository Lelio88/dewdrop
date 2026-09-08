import 'package:dewdrop/src/features/home/presentation/home_menu.dart';
import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A ListTile paints its background and its ink splash on the nearest Material
  // ancestor. The menu's tiles sit inside the sheet's translucent Container — a
  // coloured DecoratedBox — which paints OVER those effects and swallows the tap
  // feedback. ListTile reports it itself (`_debugCheckBackgroundIsHidden`), and
  // the test binding turns any reported error into a failure: pumping the sheet
  // IS the assertion, `takeException` only names it when it fires.
  testWidgets('every menu tile keeps its ink above the sheet background', (
    tester,
  ) async {
    // Tall surface: a cramped one overflows, and an overflow is reported the
    // same way — the test would then fail for the wrong reason.
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: HomeMenu(profile: Profile(id: 'me', handle: 'moi')),
          ),
        ),
      ),
    );

    expect(find.byType(ListTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
