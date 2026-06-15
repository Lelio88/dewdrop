import 'package:dewdrop/src/features/profile/domain/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromMap reads every field', () {
    final p = Profile.fromMap({
      'id': 'u1',
      'handle': 'bob',
      'display_name': 'Bob',
      'decor': 'forest:2',
      'render_mode': 'drawn',
      'quiet_start': 22,
      'quiet_end': 7,
      'quiet_tz': 'Europe/Paris',
      'default_anonymous': true,
      'sound_prefs': {
        'desert': {
          'mus': {'on': false, 'vol': 0.5},
        },
      },
    });
    expect(p.id, 'u1');
    expect(p.handle, 'bob');
    expect(p.displayName, 'Bob');
    expect(p.decor, 'forest:2');
    expect(p.renderMode, 'drawn');
    expect(p.quietStart, 22);
    expect(p.quietEnd, 7);
    expect(p.quietTz, 'Europe/Paris');
    expect(p.defaultAnonymous, true);
    expect(p.soundPrefs.forEnv('desert').mus.on, false);
    expect(p.soundPrefs.forEnv('desert').mus.vol, 0.5);
  });

  test('fromMap applies defaults for missing optional fields', () {
    final p = Profile.fromMap({'id': 'u1'});
    expect(p.handle, isNull);
    expect(p.displayName, isNull);
    expect(p.decor, 'space:0');
    expect(p.renderMode, 'photo');
    expect(p.quietStart, isNull);
    expect(p.quietTz, isNull);
    expect(p.defaultAnonymous, false);
    expect(p.soundPrefsRaw, isEmpty);
    expect(p.soundPrefs.byEnv, isEmpty);
  });

  group('hasHandle', () {
    test('true when a non-empty handle is set', () {
      expect(Profile.fromMap({'id': 'u', 'handle': 'x'}).hasHandle, true);
    });
    test('false when the handle is null', () {
      expect(Profile.fromMap({'id': 'u'}).hasHandle, false);
    });
    test('false when the handle is only whitespace', () {
      expect(Profile.fromMap({'id': 'u', 'handle': '   '}).hasHandle, false);
    });
  });
}
