import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dance_learning_app/player/metronome_sound.dart';

void main() {
  group('中立音声 home（行为不变）', () {
    test('设置槽默认值：音源普通、声音反馈关、半拍声开', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(metronomeSoundTypeProvider),
        MetronomeSoundType.normal,
      );
      expect(container.read(metronomeSoundEnabledProvider), isFalse);
      expect(container.read(metronomeHalfBeatEnabledProvider), isTrue);
    });

    test('音源可用性词表（待支持置灰口径随迁）', () {
      expect(MetronomeSoundType.normal.samplePending, isFalse);
      expect(MetronomeSoundType.vocal.samplePending, isTrue);
      expect(MetronomeSoundType.geigi.samplePending, isTrue);
    });
  });
}
