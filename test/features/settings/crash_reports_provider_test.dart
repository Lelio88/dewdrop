import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart'
    show sharedPreferencesProvider;
import 'package:dewdrop/src/features/settings/application/crash_reports_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late List<bool> applied;

  Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    applied = [];
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        crashReportingSinkProvider.overrideWithValue((enabled) async {
          applied.add(enabled);
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('crash reports opt-out', () {
    test('reports are on until the user turns them off', () async {
      final container = await containerWith({});
      expect(container.read(crashReportsProvider), isTrue);
      expect(
        crashReportsEnabled(container.read(sharedPreferencesProvider)),
        isTrue,
      );
    });

    test('turning them off persists and reaches the crash reporter', () async {
      final container = await containerWith({});
      await container.read(crashReportsProvider.notifier).set(false);

      expect(container.read(crashReportsProvider), isFalse);
      expect(applied, [false]);
      // main() reads this at the next launch, before anything can crash.
      expect(
        crashReportsEnabled(container.read(sharedPreferencesProvider)),
        isFalse,
      );
    });

    test('a stored refusal is honoured at startup', () async {
      final container = await containerWith({kCrashReportsPref: false});
      expect(container.read(crashReportsProvider), isFalse);
    });

    test('turning them back on reaches the crash reporter too', () async {
      final container = await containerWith({kCrashReportsPref: false});
      await container.read(crashReportsProvider.notifier).set(true);

      expect(container.read(crashReportsProvider), isTrue);
      expect(applied, [true]);
    });
  });
}
