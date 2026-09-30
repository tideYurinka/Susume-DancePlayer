import 'package:dance_learning_app/player/compare_recording.dart';
import 'package:dance_learning_app/player/compare_recording_clips.dart'
    show NotifierCompareRecordingChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 录制值道写缝的域内实现测试：写面直落四个跨帧
/// 值道模型，复位把相位与起录点收回待录态（推迟到微任务，容器已销毁时静默）。
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  NotifierCompareRecordingChannels channels() =>
      NotifierCompareRecordingChannels(
        phase: container.read(compareRecordingPhaseProvider.notifier),
        prepBeat: container.read(recordingPrepBeatProvider.notifier),
        recordingStart: container.read(compareRecordingStartProvider.notifier),
        armedBaselines: container.read(
          armedSurfaceBaselinesProvider.notifier,
        ),
      );

  test('写面直落值道模型', () {
    final channel = channels();
    channel.setPhase(CompareRecordingPhase.preparing);
    channel.setRecordingStart(const Duration(seconds: 12));

    expect(
      container.read(compareRecordingPhaseProvider),
      CompareRecordingPhase.preparing,
    );
    expect(
      container.read(compareRecordingStartProvider),
      const Duration(seconds: 12),
    );
  });

  test('复位把四个值道收回待录态（微任务后生效）', () async {
    final channel = channels();
    channel.setPhase(CompareRecordingPhase.recording);
    channel.setRecordingStart(const Duration(seconds: 12));

    channel.reset();
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(compareRecordingPhaseProvider),
      CompareRecordingPhase.idle,
    );
    expect(container.read(recordingPrepBeatProvider), isNull);
    expect(container.read(compareRecordingStartProvider), isNull);
    expect(container.read(armedSurfaceBaselinesProvider), isNull);
  });
}
