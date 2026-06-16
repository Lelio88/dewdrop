import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart'
    show sharedPreferencesProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kParallax = 'display_parallax';

/// Device-local toggle for the gyroscope parallax. Some people find the motion
/// distracting or get a bit motion-sick, so it can be turned off. Stored in
/// SharedPreferences (a per-device display preference, not profile data);
/// defaults to on.
class ParallaxEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_kParallax) ?? true;

  Future<void> set(bool enabled) async {
    state = enabled;
    await ref.read(sharedPreferencesProvider).setBool(_kParallax, enabled);
  }
}

final parallaxEnabledProvider = NotifierProvider<ParallaxEnabledNotifier, bool>(
  ParallaxEnabledNotifier.new,
);
