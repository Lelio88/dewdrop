import 'package:dewdrop/src/features/home/presentation/received_peek.dart';
import 'package:dewdrop/src/features/thoughts/application/thought_providers.dart';
import 'package:dewdrop/src/features/thoughts/domain/thought.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

List<ReceivedThought> _thoughts(int n) => [
  for (var i = 0; i < n; i++)
    ReceivedThought(
      id: '$i',
      createdAt: DateTime(2026).add(Duration(minutes: i)),
      isAnonymous: true, // sender null → shown as "Quelqu'un"
    ),
];

Future<void> _pump(
  WidgetTester tester, {
  required bool expanded,
  required int count,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        receivedThoughtsProvider.overrideWith((ref) async => _thoughts(count)),
      ],
      child: MaterialApp(
        home: Scaffold(
          // Bound the height: the expanded branch uses an Expanded.
          body: SizedBox(
            height: 600,
            child: ReceivedPeek(onSeeAll: () {}, expanded: expanded),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('peek shows at most 3 recent pensées', (tester) async {
    await _pump(tester, expanded: false, count: 6);
    expect(find.textContaining('a pensé à toi'), findsNWidgets(3));
  });

  testWidgets('expanded shows the whole history in place', (tester) async {
    await _pump(tester, expanded: true, count: 6);
    expect(find.textContaining('a pensé à toi'), findsNWidgets(6));
  });

  testWidgets('empty peek shows the reassuring line', (tester) async {
    await _pump(tester, expanded: false, count: 0);
    expect(find.textContaining("Personne ne t'a encore"), findsOneWidget);
  });
}
