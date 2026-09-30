import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/player/beat_presentation.dart';
import 'package:dance_learning_app/player/beat_presentation_providers.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';
import 'package:dance_learning_app/player/native_scheduled_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/uniform_test_grid.dart';

/// 容器销毁后的接缝读取纪律（宿主拆场缝）：推进链的链节在微任务里才开跑，
/// 而容器可能在链节开跑之前就销毁（测试拆场、页面随容器退场）。此时链节
/// 必须直接丢弃，不得经接缝工厂读已销毁容器的 `ref`——那会把
/// `UnmountedRefException` 送进无人 await 的链，报成「测试体已通过之后」的
/// 未捕获错误，并归因到当时正在跑的任意用例。
BeatPresentationContext _context(BeatGrid grid) => BeatPresentationContext(
  grid: grid,
  phase: BeatPhase(grid: grid),
  segmentLines: const [],
  firstLine: Duration.zero,
  source: metronomeSourceEntryOfId(kNormalSourceId),
  slotVolumeOf: (slot) => 1.0,
  halfBeatLines: const [],
  halfBeatEnabled: false,
  avSyncDelayMs: 0,
  rate: 1.0,
  playing: true,
  soundEnabled: true,
  gridError: false,
  sessionActive: false,
);

void main() {
  final grid = UniformTestGrid(beatCount: 32);

  test('容器销毁后推进链不再读接缝：在途链节丢弃，链接正常收尾', () async {
    final container = ProviderContainer(
      overrides: [
        // 设备渲染器换成本机哑实现：本用例只关心接缝被读的时机，不关心发声，
        // 也避免真实渲染器去碰音源设置链。
        beatAudioRendererProvider.overrideWith((ref) => BeatAudioRenderer()),
      ],
    );
    addTearDown(container.dispose);
    final presentation = container.read(beatPresentationProvider);

    // 排一个推进链节（微任务里才开跑），不等它跑就在同一同步段销毁容器。
    presentation.onFrame(_context(grid), Duration.zero);
    container.dispose();

    // 收尾量即推进链：修复前这里抛出 UnmountedRefException。
    await presentation.settled;
  });
}
