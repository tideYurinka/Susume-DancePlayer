// 练习记账门纯件直测：
// 声明表逐语境判定（每种语境一例）+ 事实求值边界 + 穷尽性结构断言。
// 零依赖：不启 widget 环境、不装引擎。
import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/persistence/practice_accounting.dart';

void main() {
  group('声明表逐语境判定', () {
    test('在播类语境一律计入，依据「引擎在播」', () {
      const inPlay = [
        PracticeContext.watchPlaying,
        PracticeContext.editPlaying,
        PracticeContext.eightBeatStandby,
        PracticeContext.comparePlayback,
        PracticeContext.compareControlLayer,
        PracticeContext.framingAdjust,
        PracticeContext.threeFingerJump,
        PracticeContext.segmentSelectionJump,
        PracticeContext.segmentLoopJumpBack,
        PracticeContext.trackBandInRangeDrag,
        PracticeContext.clipEndpointTrimDrag,
        PracticeContext.volumeBrightnessMirrorDirectionLock,
        PracticeContext.recordingLiveFollow,
      ];
      expect(inPlay, hasLength(13));
      for (final context in inPlay) {
        final verdict = practiceVerdictOf(context);
        expect(verdict.counted, isTrue, reason: '$context 应计入');
        expect(verdict.basis, PracticeBasis.enginePlaying);
      }
    });

    test('练习片段回看在飞不计，依据「事实：激活非空 ∧ 片段可解析」', () {
      final verdict = practiceVerdictOf(PracticeContext.clipReviewInFlight);
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.clipReviewInFlightFact);
      expect(verdict.rationale, contains('激活非空'));
    });

    test('录制准备期不计，依据「事实：相位 = preparing」', () {
      final verdict = practiceVerdictOf(PracticeContext.recordingPreparing);
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.preparingPhaseFact);
      expect(verdict.rationale, contains('preparing'));
    });

    test('延迟预备播放期不计，依据「事实：相位 = preparing」', () {
      final verdict = practiceVerdictOf(PracticeContext.delayedPlayPreparing);
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.preparingPhaseFact);
      expect(verdict.rationale, contains('preparing'));
    });

    test('引擎不在播的语境不计（校准/循环提示/备注/帧步进/scrub/拖线/越界）', () {
      const notPlaying = [
        PracticeContext.avSyncCalibration,
        PracticeContext.endLoopPromptCountdown,
        PracticeContext.noteEditing,
        PracticeContext.frameStepping,
        PracticeContext.fullscreenScrub,
        PracticeContext.annotationLineDragPreview,
        PracticeContext.trackBandDragOutOfRange,
      ];
      expect(notPlaying, hasLength(7));
      for (final context in notPlaying) {
        final verdict = practiceVerdictOf(context);
        expect(verdict.counted, isFalse, reason: '$context 应不计');
        expect(verdict.basis, PracticeBasis.engineNotPlaying);
      }
    });

    test('解析窗口不计，依据「标识未定」', () {
      final verdict = practiceVerdictOf(PracticeContext.videoParsingWindow);
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.identityUnresolved);
    });

    test('练习侧第二引擎单独播放不计，依据「不在口径内」', () {
      final verdict =
          practiceVerdictOf(PracticeContext.secondEngineSoloPlayback);
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.outOfScope);
    });
  });

  group('事实求值', () {
    test('全空事实（引擎不在播）不计', () {
      final verdict = evaluatePracticeAccounting(
        const PracticeAccountingFacts(),
      );
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.engineNotPlaying);
    });

    test('引擎在播且无专属事实成立 ⇒ 计入', () {
      final verdict = evaluatePracticeAccounting(
        const PracticeAccountingFacts(enginePlaying: true),
      );
      expect(verdict.counted, isTrue);
      expect(verdict.basis, PracticeBasis.enginePlaying);
    });

    test('回看在飞（激活非空 ∧ 片段可解析）即使引擎在播也不计', () {
      final verdict = evaluatePracticeAccounting(
        const PracticeAccountingFacts(
          enginePlaying: true,
          clipReviewInFlight: true,
        ),
      );
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.clipReviewInFlightFact);
    });

    test('录制准备期即使引擎在播也不计', () {
      final verdict = evaluatePracticeAccounting(
        const PracticeAccountingFacts(
          enginePlaying: true,
          recordingPreparing: true,
        ),
      );
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.preparingPhaseFact);
    });

    test('延迟预备播放期即使引擎在播也不计', () {
      final verdict = evaluatePracticeAccounting(
        const PracticeAccountingFacts(
          enginePlaying: true,
          delayedPlayPreparing: true,
        ),
      );
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.preparingPhaseFact);
    });

    test('越过起点后（预备事实撤销）在播即计入', () {
      final verdict = evaluatePracticeAccounting(
        const PracticeAccountingFacts(
          enginePlaying: true,
          delayedPlayPreparing: false,
        ),
      );
      expect(verdict.counted, isTrue);
      expect(verdict.basis, PracticeBasis.enginePlaying);
    });

    test('回看在飞与录制准备同时成立 ⇒ 不计', () {
      final verdict = evaluatePracticeAccounting(
        const PracticeAccountingFacts(
          enginePlaying: true,
          clipReviewInFlight: true,
          recordingPreparing: true,
        ),
      );
      expect(verdict.counted, isFalse);
    });

    test('解析窗口（标识未定）不计，压过在播与专属事实', () {
      final verdict = evaluatePracticeAccounting(
        const PracticeAccountingFacts(
          enginePlaying: true,
          videoIdentified: false,
        ),
      );
      expect(verdict.counted, isFalse);
      expect(verdict.basis, PracticeBasis.identityUnresolved);
    });

    test('悬空激活保持今天口径：激活在但片段不可解析 ⇒ 在播即计入', () {
      // 悬空激活不构成「回看在飞」事实（要求激活非空 ∧ 片段可解析）。
      final verdict = evaluatePracticeAccounting(
        const PracticeAccountingFacts(enginePlaying: true),
      );
      expect(verdict.counted, isTrue);
    });
  });

  group('穷尽性护栏', () {
    test('声明表行数 == 枚举取值数，且逐值可查', () {
      final table = {
        for (final context in PracticeContext.values)
          context: practiceVerdictOf(context),
      };
      // 25 是防枚举膨胀的钉子：加语境必须连判定行与用例一起加。
      expect(table.length, 25);
      expect(table.keys.toSet(), PracticeContext.values.toSet());
    });
  });
}
