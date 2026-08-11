import 'package:dewdrop/src/features/ambient/application/audio_focus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.dewdrop/audio_focus');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'request' ? true : null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Pushes a native → Dart callback through the real channel codec.
  Future<void> fireNative(String method) => messenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(MethodCall(method)),
    (_) {},
  );

  AudioFocus newFocus() => AudioFocus(channel: channel, supported: true);

  group('AudioFocus', () {
    test('requests once, then stays quiet while already held', () async {
      final focus = newFocus();
      await focus.request();
      await focus.request();
      expect(calls, ['request']);
    });

    test('abandons only what it holds', () async {
      final focus = newFocus();
      await focus.abandon(); // nothing held yet
      expect(calls, isEmpty);

      await focus.request();
      await focus.abandon();
      await focus.abandon();
      expect(calls, ['request', 'abandon']);
    });

    test('a focus loss notifies without abandoning the request', () async {
      // Abandoning here would unregister the native listener and forfeit the
      // onFocusGained that ends a transient loss (a phone call).
      final focus = newFocus();
      var lost = 0;
      var gained = 0;
      focus.bind(onLost: () => lost++, onGained: () => gained++);

      await focus.request();
      await fireNative('onFocusLost');

      expect(lost, 1);
      expect(calls, ['request'], reason: 'no abandon on loss');

      await fireNative('onFocusGained');
      expect(gained, 1);
    });

    test('re-requests after a loss', () async {
      final focus = newFocus();
      focus.bind(onLost: () {}, onGained: () {});
      await focus.request();
      await fireNative('onFocusLost');
      await focus.request();
      expect(calls, ['request', 'request']);
    });

    test('is a no-op on unsupported platforms', () async {
      final focus = AudioFocus(channel: channel, supported: false);
      focus.bind(onLost: () {}, onGained: () {});
      await focus.request();
      await focus.abandon();
      expect(calls, isEmpty);
    });
  });
}
