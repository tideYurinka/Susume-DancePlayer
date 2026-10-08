import 'package:dance_learning_app/cast/cast_render_activity.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/dance/video_copy_presence.dart'
    show videoCopyPresenceProvider;
import 'package:dance_learning_app/player/av_sync.dart';
import 'package:dance_learning_app/player/av_sync_session.dart';
import 'package:dance_learning_app/player/cast_entry_gate.dart';
import 'package:dance_learning_app/player/cast_prep_panel.dart'
    show kCastPrepCopyMissingText;
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'package:dance_learning_app/player/play_tool_table.dart';
import 'package:dance_learning_app/player/tool_slots.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_video_copy_presence.dart';

/// 无输出设备替身（事实装配用例不碰平台通道）。
class _NoAudioDevice implements AudioOutputDeviceController {
  @override
  Future<AvSyncDeviceInfo?> get() async => null;

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream => const Stream.empty();
}

/// 只读一份固定会话态的校准会话替身（事实装配用例：不跑真实进入流程）。
class _ActiveAvSync extends AvSyncCalibrationSessionModel {
  @override
  AvSyncCalibrationSessionState build() =>
      const AvSyncCalibrationSessionState(active: true);
}

/// 投屏入口那五条门（票 #35）：**副本丢失 / 音画同步校准中 /
/// 录制中（含准备期）/ 对比态或取景调节态 / 渲染进行中**各自把入口置灰、
/// 按下去只解释原因、绝不执行动作。
///
/// 判定表复用底排标注工具区那一条（[evaluateDeclaredGates] 与
/// [kToolGatePriority]），可点性照「置灰、可点、弹原因」那一行取——本文件
/// 只钉声明面（槽声明了哪五条、判定/可点性取值），生产落点（入口置灰与按下
/// 弹哪一句）在 `cast_mode_test.dart` 与 `cast_entry_gate.dart`。
void main() {
  /// 声明次序即优先级声明次序：第一条先报。
  const declaredCastGates = [
    ToolGateKind.castCopyMissing,
    ToolGateKind.castAvSyncCalibrating,
    ToolGateKind.castRecording,
    ToolGateKind.castCompareOrFraming,
    ToolGateKind.castRendering,
  ];

  test('投屏槽声明的门就是这五条', () {
    expect(kPlayToolCast.gates, declaredCastGates);
  });

  test('门优先级覆盖全部 ToolGateKind：加取值漏补即红（不会静默不判）', () {
    expect(kToolGatePriority.toSet(), ToolGateKind.values.toSet());
  });

  group('五条门各自把入口置灰为「可点、只解释原因」', () {
    test('副本丢失', () {
      final verdict = evaluateDeclaredGates(
        kPlayToolCast.gates.toSet(),
        const ToolFacts(castCopyMissing: true),
      );
      expect(verdict.available, isFalse);
      expect(verdict.kind, ToolGateKind.castCopyMissing);
      expect(verdict.tappable, isTrue, reason: '灰着但仍可点：按下去只解释原因');
    });

    test('音画同步校准中', () {
      final verdict = evaluateDeclaredGates(
        kPlayToolCast.gates.toSet(),
        const ToolFacts(castAvSyncCalibrating: true),
      );
      expect(verdict.available, isFalse);
      expect(verdict.kind, ToolGateKind.castAvSyncCalibrating);
      expect(verdict.tappable, isTrue);
    });

    test('录制中或录制准备中', () {
      final verdict = evaluateDeclaredGates(
        kPlayToolCast.gates.toSet(),
        const ToolFacts(castRecording: true),
      );
      expect(verdict.available, isFalse);
      expect(verdict.kind, ToolGateKind.castRecording);
      expect(verdict.tappable, isTrue);
    });

    test('对比态或取景调节态', () {
      final verdict = evaluateDeclaredGates(
        kPlayToolCast.gates.toSet(),
        const ToolFacts(castCompareOrFraming: true),
      );
      expect(verdict.available, isFalse);
      expect(verdict.kind, ToolGateKind.castCompareOrFraming);
      expect(verdict.tappable, isTrue);
    });

    test('渲染进行中', () {
      final verdict = evaluateDeclaredGates(
        kPlayToolCast.gates.toSet(),
        const ToolFacts(castRendering: true),
      );
      expect(verdict.available, isFalse);
      expect(verdict.kind, ToolGateKind.castRendering);
      expect(verdict.tappable, isTrue);
    });
  });

  test('一条都不命中：入口正常可用', () {
    final verdict = evaluateDeclaredGates(
      kPlayToolCast.gates.toSet(),
      const ToolFacts(),
    );
    expect(verdict.available, isTrue);
    expect(verdict.kind, isNull);
  });

  test('多条同时命中：按门优先级取第一条（副本丢失压倒一切）', () {
    final verdict = evaluateDeclaredGates(
      kPlayToolCast.gates.toSet(),
      const ToolFacts(
        castRendering: true,
        castRecording: true,
        castCopyMissing: true,
      ),
    );
    expect(verdict.kind, ToolGateKind.castCopyMissing);
  });

  test('可点性派生：命中门时置灰仍可点；无门时随硬启用位', () {
    expect(
      playToolTappable(
        kPlayToolCast,
        hasSubject: true,
        enabled: false,
        facts: const ToolFacts(castRecording: true),
      ),
      isTrue,
      reason: '灰着的入口按下去要能解释原因',
    );
    expect(
      playToolTappable(kPlayToolCast, hasSubject: true, enabled: true),
      isTrue,
    );
    expect(
      playToolTappable(kPlayToolCast, hasSubject: true, enabled: false),
      isFalse,
    );
  });

  test('这套门只挂在投屏槽上：别的槽门清单一位不变', () {
    for (final slot in [
      kPlayToolUndo,
      kPlayToolRedo,
      kPlayToolAvSync,
      kPlayToolBeatPrompt,
      kPlayToolMirror,
      kPlayToolLocalMirror,
      kPlayToolSpeedSettings,
      kPlayToolCompare,
      kPlayToolFramingAdjust,
      kPlayToolDisconnectCast,
      kPlayToolGuide,
      kPlayToolMore,
    ]) {
      expect(
        slot.gates.where(declaredCastGates.contains),
        isEmpty,
        reason: '${slot.key} 不该声明投屏入口的门',
      );
    }
  });

  group('五条门的事实装配（唯一装配点）', () {
    const path = '/videos/a.mp4';

    ProviderContainer makeContainer({Set<String> missingPaths = const {}}) {
      final fresh = ProviderContainer(
        overrides: [
          // 校准会话那条读面挂在播放内核与平台通道上：事实装配用例
          // 不碰真内核、不碰平台。
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          audioOutputDeviceControllerProvider.overrideWithValue(
            _NoAudioDevice(),
          ),
          videoCopyPresenceProvider.overrideWithValue(
            FakeVideoCopyPresence(missingPaths: missingPaths),
          ),
        ],
      );
      addTearDown(fresh.dispose);
      return fresh;
    }

    CastEntryFacts factsOf(ProviderContainer container) =>
        container.read(castEntryFactsProvider(path));

    test('缺省：五条都不成立', () {
      final facts = factsOf(makeContainer());
      expect(facts.copyMissing, isFalse);
      expect(facts.avSyncCalibrating, isFalse);
      expect(facts.recording, isFalse);
      expect(facts.compareOrFraming, isFalse);
      expect(facts.rendering, isFalse);
      expect(castEntryVerdict(facts).available, isTrue);
      expect(castEntryVerdict(facts).kind, isNull);
    });

    test('副本丢失：按这支舞的视频副本路径问存在性', () {
      final facts = factsOf(makeContainer(missingPaths: {path}));
      expect(facts.copyMissing, isTrue);
      expect(castEntryVerdict(facts).kind, ToolGateKind.castCopyMissing);
      expect(castEntryVerdict(facts).tappable, isTrue, reason: '灰着但按得动');
    });

    test('音画同步校准中：会话活跃即命中', () {
      final container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          audioOutputDeviceControllerProvider.overrideWithValue(
            _NoAudioDevice(),
          ),
          videoCopyPresenceProvider.overrideWithValue(FakeVideoCopyPresence()),
          avSyncCalibrationSessionProvider.overrideWith(_ActiveAvSync.new),
        ],
      );
      addTearDown(container.dispose);

      final facts = factsOf(container);
      expect(facts.avSyncCalibrating, isTrue);
      expect(castEntryVerdict(facts).kind, ToolGateKind.castAvSyncCalibrating);
    });

    test('录制中或录制准备中：相位非待录态即命中（两值都算）', () {
      for (final phase in const [
        CompareRecordingPhase.preparing,
        CompareRecordingPhase.recording,
      ]) {
        final container = makeContainer();
        container.read(compareRecordingPhaseProvider.notifier).set(phase);
        final facts = factsOf(container);
        expect(facts.recording, isTrue, reason: '$phase');
        expect(castEntryVerdict(facts).kind, ToolGateKind.castRecording);
      }
    });

    test('对比态：对比-控制层命中（控制层展开、那枚入口在场）', () {
      final container = makeContainer();
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      final facts = factsOf(container);
      expect(facts.compareOrFraming, isTrue);
      expect(castEntryVerdict(facts).kind, ToolGateKind.castCompareOrFraming);
    });

    test('取景调节态：两个取景取值都命中', () {
      for (final mode in const [
        PlayerSessionMode.framing,
        PlayerSessionMode.compareFraming,
      ]) {
        final container = makeContainer();
        container.read(playerSessionProvider.notifier).enter(mode);
        expect(factsOf(container).compareOrFraming, isTrue, reason: '$mode');
      }
    });

    test('渲染进行中：渲染活动事实由渲染编排那处写入', () {
      final container = makeContainer();
      expect(factsOf(container).rendering, isFalse);
      container.read(castRenderInProgressProvider.notifier).begin();
      final facts = factsOf(container);
      expect(facts.rendering, isTrue);
      expect(castEntryVerdict(facts).kind, ToolGateKind.castRendering);
      container.read(castRenderInProgressProvider.notifier).end();
      expect(factsOf(container).rendering, isFalse);
    });
  });

  group('门的一句话（按下去弹这一句）', () {
    test('五条门各有唯一一句（文案改了要能在测试里看见）', () {
      expect(
        castEntryGateText(ToolGateKind.castCopyMissing),
        '这支舞的视频副本不在本机，先把副本找回来再投屏',
      );
      expect(
        castEntryGateText(ToolGateKind.castAvSyncCalibrating),
        '音画同步校准中，先退出校准再投屏',
      );
      expect(
        castEntryGateText(ToolGateKind.castRecording),
        '录制中（含准备中）不能投屏，先停录',
      );
      expect(
        castEntryGateText(ToolGateKind.castCompareOrFraming),
        '先退出对比或取景调整，再投屏',
      );
      expect(castEntryGateText(ToolGateKind.castRendering), '正在渲染投屏副本，渲完再投');
    });

    test('副本丢失那一句与准备面板里那一句是同一句（同一事实一个说法）', () {
      expect(
        castEntryGateText(ToolGateKind.castCopyMissing),
        kCastPrepCopyMissingText,
      );
    });

    test('不是投屏入口的门：显式报错，不静默给一句错话', () {
      for (final gate in const [
        ToolGateKind.loading,
        ToolGateKind.noSubject,
        ToolGateKind.locked,
        ToolGateKind.gridNotReady,
        ToolGateKind.previewOutOfBounds,
      ]) {
        expect(
          () => castEntryGateText(gate),
          throwsStateError,
          reason: '$gate',
        );
      }
    });
  });
}
