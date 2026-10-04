import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手势目标起手门禁声明表 + 起手前纯读：
/// ProviderContainer 直测模块 interface（仿 annotation_editor_compare_
/// readonly_test 模板）。
///
/// 验收：目标声明表覆盖全部 19 族手势目标（无门 = 显式空清单）；verb
/// 支撑的目标与逐 verb 声明（[AnnotationEditor.verbGateReasons]）一致
/// （两张表一致性断言）；起手前纯读完全由声明 + 两个门禁事实回答——
/// 去掉声明里的 `compareReadonly` 即放行（「对比态下改不动」由声明回
/// 答，不依赖对比行集恰好不含那些行）。
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);

  void enableLock() => container.read(layoutLockedProvider.notifier).toggle();

  void enterCompare() => container
      .read(playerSessionProvider.notifier)
      .enter(PlayerSessionMode.compareEditing);

  group('目标声明表覆盖全部手势目标（无门 = 显式空清单）', () {
    test('逐 target 声明的门禁原因集合', () {
      final expected =
          <(AnnotationGestureTarget, Set<AnnotationEditGateReason>)>[
            // verb 支撑（从逐 verb 声明取值）。
            (
              AnnotationGestureTarget.segmentLineMove,
              {
                AnnotationEditGateReason.userLayoutLock,
                AnnotationEditGateReason.compareReadonly,
                AnnotationEditGateReason.memberSchemeReadonly,
              },
            ),
            (
              AnnotationGestureTarget.halfBeatLineMove,
              {
                AnnotationEditGateReason.compareReadonly,
                AnnotationEditGateReason.memberSchemeReadonly,
              },
            ),
            (
              AnnotationGestureTarget.rangeBoundaryDrag,
              {
                AnnotationEditGateReason.userLayoutLock,
                AnnotationEditGateReason.compareReadonly,
                AnnotationEditGateReason.memberSchemeReadonly,
              },
            ),
            (
              AnnotationGestureTarget.localMirrorMove,
              {
                AnnotationEditGateReason.compareReadonly,
                AnnotationEditGateReason.memberSchemeReadonly,
              },
            ),
            (
              AnnotationGestureTarget.localMirrorEdgeDrag,
              {
                AnnotationEditGateReason.compareReadonly,
                AnnotationEditGateReason.memberSchemeReadonly,
              },
            ),
            (
              AnnotationGestureTarget.noteMove,
              {
                AnnotationEditGateReason.compareReadonly,
                AnnotationEditGateReason.memberSchemeReadonly,
              },
            ),
            (
              AnnotationGestureTarget.noteEdgeDrag,
              {
                AnnotationEditGateReason.compareReadonly,
                AnnotationEditGateReason.memberSchemeReadonly,
              },
            ),
            // 练习片段截取：不声明任何门禁原因（显式空清单）——对比态自己的
            // 写点，既不受对比态只读、也不受锁定分段。
            (AnnotationGestureTarget.practiceClipTrim, const {}),
            // 无 verb 的目标：就地声明；无门 = 显式空清单。
            (AnnotationGestureTarget.segmentLineTap, const {}),
            (AnnotationGestureTarget.controlKnobTap, const {}),
            (
              AnnotationGestureTarget.halfBeatLineTap,
              {AnnotationEditGateReason.compareReadonly},
            ),
            (AnnotationGestureTarget.rangeBoundaryTap, const {}),
            (AnnotationGestureTarget.localMirrorRowTap, const {}),
            (
              AnnotationGestureTarget.noteRowTap,
              {AnnotationEditGateReason.compareReadonly},
            ),
            (
              AnnotationGestureTarget.noteLockLongPress,
              {AnnotationEditGateReason.compareReadonly},
            ),
            (AnnotationGestureTarget.practiceClipBlockTap, const {}),
            (AnnotationGestureTarget.learningTrackTap, const {}),
            (AnnotationGestureTarget.previewLineDrag, const {}),
            (AnnotationGestureTarget.blankSurfacePinchPan, const {}),
          ];
      expect(
        AnnotationGestureTarget.values.toSet(),
        expected.map((e) => e.$1).toSet(),
        reason: '枚举与声明表逐条对应：加目标必须同时补声明（穷尽 switch）',
      );
      for (final (target, reasons) in expected) {
        expect(
          gestureTargetGateReasons(target),
          reasons,
          reason: '$target 的声明与预期门禁集合不一致',
        );
      }
    });
  });

  group('两张表一致性：verb 支撑的目标 == 逐 verb 声明', () {
    test('逐 target 与代表 verb 的声明集合相等', () {
      final pairs = <(AnnotationGestureTarget, AnnotationEdit)>[
        (
          AnnotationGestureTarget.segmentLineMove,
          const MoveSegmentLine(index: 0, to: Duration.zero),
        ),
        (
          AnnotationGestureTarget.halfBeatLineMove,
          const MoveHalfBeatLine(index: 0, to: Duration.zero),
        ),
        (AnnotationGestureTarget.rangeBoundaryDrag, const SetVideoRange()),
        (
          AnnotationGestureTarget.localMirrorMove,
          const MoveLocalMirrorFragment(index: 0, to: Duration.zero),
        ),
        (
          AnnotationGestureTarget.localMirrorEdgeDrag,
          const DragLocalMirrorFragmentEdge(
            index: 0,
            edge: IntervalEdge.start,
            to: Duration.zero,
          ),
        ),
        (
          AnnotationGestureTarget.noteMove,
          const MoveNote(index: 0, to: Duration.zero),
        ),
        (
          AnnotationGestureTarget.noteEdgeDrag,
          const DragNoteEdge(
            index: 0,
            edge: IntervalEdge.start,
            to: Duration.zero,
          ),
        ),
        (
          AnnotationGestureTarget.practiceClipTrim,
          const TrimPracticeClip(
            clipId: '',
            edge: IntervalEdge.start,
            to: Duration.zero,
          ),
        ),
      ];
      for (final (target, verb) in pairs) {
        expect(
          gestureTargetGateReasons(target),
          AnnotationEditor.verbGateReasons(verb),
          reason: '目标声明表必须与逐 verb 声明同源（不抄第二份）',
        );
      }
    });
  });

  group('起手前纯读：拒绝与否完全由声明 + 门禁事实回答', () {
    test('无锁、非对比态：没有任何目标被拒', () {
      for (final target in AnnotationGestureTarget.values) {
        expect(
          editor().gestureStartRejected(target),
          isFalse,
          reason: '$target 在无门禁事实时不应被拒',
        );
      }
    });

    test('锁定分段：被拒 ⇔ 声明含用户锁（去掉声明即放行）', () {
      enableLock();
      for (final target in AnnotationGestureTarget.values) {
        expect(
          editor().gestureStartRejected(target),
          gestureTargetGateReasons(target)
              .contains(AnnotationEditGateReason.userLayoutLock),
          reason: '$target 的起手拒绝必须由声明里的用户锁回答',
        );
      }
    });

    test('对比态只读：被拒 ⇔ 声明含对比态只读（去掉声明即放行）', () {
      enterCompare();
      for (final target in AnnotationGestureTarget.values) {
        expect(
          editor().gestureStartRejected(target),
          gestureTargetGateReasons(target)
              .contains(AnnotationEditGateReason.compareReadonly),
          reason: '$target 的起手拒绝必须由声明里的对比态只读回答',
        );
      }
    });

    test('四族对比态只读显式化：对比态下改不动由声明回答', () {
      enterCompare();
      expect(
        editor().gestureStartRejected(AnnotationGestureTarget.segmentLineMove),
        isTrue,
      );
      expect(
        editor().gestureStartRejected(
          AnnotationGestureTarget.rangeBoundaryDrag,
        ),
        isTrue,
      );
      expect(
        editor().gestureStartRejected(AnnotationGestureTarget.localMirrorMove),
        isTrue,
      );
      expect(
        editor().gestureStartRejected(
          AnnotationGestureTarget.localMirrorEdgeDrag,
        ),
        isTrue,
      );
      // 片段截取不声明任何门禁原因：对比态下照常参与（它是对比态自己的
      // 写点），锁定分段下也照常参与。
      expect(
        editor().gestureStartRejected(AnnotationGestureTarget.practiceClipTrim),
        isFalse,
      );
    });

    test('起手分段锁拒：锁开着时 ⇔ 声明含用户锁（加槽漏补即编译报错）', () {
      enableLock();
      for (final target in AnnotationGestureTarget.values) {
        expect(
          editor().gestureStartRejectedBySegmentLock(target),
          gestureTargetGateReasons(target)
              .contains(AnnotationEditGateReason.userLayoutLock),
          reason: '$target 的锁拒必须由声明里的用户锁回答',
        );
      }
    });

    test('起手分段锁拒：对比态只读不是分段锁（不弹「已锁定分段」）', () {
      enterCompare();
      expect(
        editor().gestureStartRejected(AnnotationGestureTarget.segmentLineMove),
        isTrue,
        reason: '对比态下仍被拒（前置）',
      );
      expect(
        editor().gestureStartRejectedBySegmentLock(
          AnnotationGestureTarget.segmentLineMove,
        ),
        isFalse,
      );
      expect(
        editor().gestureStartRejectedBySegmentLock(
          AnnotationGestureTarget.localMirrorMove,
        ),
        isFalse,
      );
    });
  });
}
