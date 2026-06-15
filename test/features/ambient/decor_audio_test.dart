import 'dart:io';

import 'package:dewdrop/decor/environment.dart';
import 'package:dewdrop/src/features/ambient/application/ambient_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every environment has an audio recipe', () {
    for (final e in Environment.values) {
      expect(kDecorAudio[e.name], isNotNull, reason: 'no audio recipe for ${e.name}');
    }
  });

  test('each recipe has an ambiance and at least one music variant', () {
    for (final entry in kDecorAudio.entries) {
      expect(entry.value.ambiance, isNotEmpty, reason: '${entry.key} ambiance');
      expect(entry.value.music, isNotEmpty, reason: '${entry.key} music');
    }
  });

  test('each secondary category has a label, clips, and a sane interval', () {
    for (final entry in kDecorAudio.entries) {
      entry.value.secondaries.forEach((key, cat) {
        expect(cat.label, isNotEmpty, reason: '${entry.key}.$key label');
        expect(cat.clips, isNotEmpty, reason: '${entry.key}.$key clips');
        expect(cat.minGap <= cat.maxGap, true,
            reason: '${entry.key}.$key minGap must be ≤ maxGap');
        expect(cat.volume, inInclusiveRange(0.0, 1.0));
      });
    }
  });

  // The most valuable check: every asset the engine will try to play must exist
  // on disk. Catches a typo or a forgotten file in the audio pipeline.
  test('every referenced audio asset exists on disk', () {
    final missing = <String>[];
    void check(String rel) {
      if (!File('assets/audio/$rel').existsSync()) missing.add(rel);
    }

    for (final cfg in kDecorAudio.values) {
      check('${cfg.ambiance}.ogg');
      for (final m in cfg.music) {
        check('$m.ogg');
      }
      for (final cat in cfg.secondaries.values) {
        for (final clip in cat.clips) {
          check('oneshot/$clip.ogg');
        }
      }
    }

    expect(missing, isEmpty, reason: 'missing audio assets:\n${missing.join('\n')}');
  });
}
