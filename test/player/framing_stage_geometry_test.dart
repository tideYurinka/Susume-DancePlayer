/// 单画面取景几何直测：**上屏画面矩形**（贴纸尺寸分数与数拍落位的参考矩形、
/// 进度取消区、角落提示卡、局部镜像标识与画面手势分母共用的那唯一一份几何）
/// 与选区内容在可用区里的画面矩形。零 widget 环境、纯输入输出。
library;

import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/player/compare_framing_view.dart';
import 'package:dance_learning_app/player/editor_skeleton.dart';
import 'package:dance_learning_app/player/framing_stage.dart';
import 'package:flutter/rendering.dart' show Rect;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 竖屏编辑面贴底骨架（带 100、带顶 50、画面区 200）——合成值，带高与源比
  /// 不自洽，用来钉住「画面条在带里居中」那条。
  const stickSkeleton = EditorSkeleton(
    compact: false,
    portrait: true,
    pictureAreaHeight: 200,
    picturePlacement: PicturePlacement.stickToBottom,
    pictureBandHeight: 100,
    pictureBandTop: 50,
  );

  /// 横屏编辑面骨架（不分配画面带）。
  const backgroundSkeleton = EditorSkeleton(
    compact: false,
    portrait: false,
    pictureAreaHeight: 0,
    picturePlacement: PicturePlacement.background,
    pictureBandHeight: 0,
    pictureBandTop: 0,
  );

  /// 左半区选区：内容比 = 源比 ÷ 2（内容像素宽 0.5、高 1）。
  const leftHalf = FramingSelection(left: 0, top: 0, right: 0.5, bottom: 1);

  group('framedContentRectInStage（选区内容在可用区里的画面矩形）', () {
    test('未调过（无选区）= 源画面 contain 基座本身', () {
      final rect = framedContentRectInStage(
        stage: const Rect.fromLTWH(0, 0, 800, 600),
        aspectRatio: 16 / 9,
        sticksToBottom: false,
        selection: null,
      );
      expect(rect, const Rect.fromLTWH(0, 75, 800, 450));
    });

    test('左半区选区：内容按 contain 放大到高充满、水平居中到可用区中心', () {
      // 内容=400×450 像素，可用区 800×600 → 放大 800/400 与 600/450 取小
      // = 4/3；显示 533.3×600，中心对到可用区中心 (400, 300)。
      final rect = framedContentRectInStage(
        stage: const Rect.fromLTWH(0, 0, 800, 600),
        aspectRatio: 16 / 9,
        sticksToBottom: false,
        selection: leftHalf,
      );
      expect(rect.left, closeTo(133.333, 0.01));
      expect(rect.top, closeTo(0, 0.01));
      expect(rect.width, closeTo(533.333, 0.01));
      expect(rect.height, closeTo(600, 0.01));
    });

    test('贴底可用区未调过：下缘贴住可用区下缘（与未取景贴底逐像素一致）', () {
      final rect = framedContentRectInStage(
        stage: const Rect.fromLTWH(0, 100, 800, 500),
        aspectRatio: 16 / 9,
        sticksToBottom: true,
        selection: null,
      );
      expect(rect, const Rect.fromLTWH(0, 150, 800, 450));
    });

    test('宽高比未知：画面即容器、无变换（返回可用区本身）', () {
      final stage = const Rect.fromLTWH(0, 100, 800, 500);
      expect(
        framedContentRectInStage(
          stage: stage,
          aspectRatio: null,
          sticksToBottom: true,
          selection: leftHalf,
        ),
        stage,
      );
    });
  });

  group('pictureRectOnScreen（上屏画面矩形的唯一求解点）', () {
    Rect rectFor({
      Size screen = const Size(800, 600),
      double systemTopInset = 0,
      double? aspectRatio = 16 / 9,
      EditorSkeleton? skeleton,
      FramingSelection? selection,
    }) => pictureRectOnScreen(
      screen: screen,
      systemTopInset: systemTopInset,
      skeleton: skeleton,
      aspectRatio: aspectRatio,
      selection: selection,
    );

    test('观看态未调过：整屏 contain 居中（宽限高）', () {
      expect(rectFor(), const Rect.fromLTWH(0, 75, 800, 450));
    });

    test('观看态竖屏 16:9：满宽、上下留黑，画面居中（不按系统栏内缩截一刀）', () {
      final rect = rectFor(screen: const Size(668, 1368), systemTopInset: 24);
      expect(rect.left, 0);
      expect(rect.width, 668);
      expect(rect.height, closeTo(668 * 9 / 16, 0.01));
      expect(rect.top, greaterThan(24), reason: '上方是黑边：画面圆心不在屏幕顶');
      expect(rect.center.dy, closeTo(1368 / 2, 0.01));
    });

    test('高限宽（竖向源在竖屏放不下）：左右留黑、垂直充满', () {
      final rect = rectFor(screen: const Size(400, 800), aspectRatio: 0.4);
      expect(rect.width, closeTo(800 * 0.4, 0.1));
      expect(rect.left, closeTo((400 - 320) / 2, 0.1));
      expect(rect.top, 0);
      expect(rect.height, 800);
    });

    test('观看态左半区选区（取景后取值）：内容高充满、左右留黑', () {
      final rect = rectFor(selection: leftHalf);
      expect(rect.left, closeTo(133.333, 0.01));
      expect(rect.width, closeTo(533.333, 0.01));
      expect(rect.height, closeTo(600, 0.01));
    });

    test('取景态内按整帧：选区传 null 与未调过同一份（画面整帧显示）', () {
      expect(rectFor(selection: null), rectFor());
      expect(
        rectFor(selection: const FramingSelection.fullFrame()),
        rectFor(selection: null),
        reason: '整帧选区与未调过在显示上不可区分',
      );
    });

    test('竖屏编辑贴底骨架：可用区取画面带（带顶按系统栏顶内缩换算）', () {
      // 带 668×100 里 16:9 画面 contain = 177.78×100、水平居中。
      final rect = rectFor(
        screen: const Size(668, 1368),
        systemTopInset: 24,
        skeleton: stickSkeleton,
      );
      const bandTop = 24 + kEditorTopBarHeight + 50;
      expect(rect.top, closeTo(bandTop, 0.01));
      expect(rect.height, closeTo(100, 0.01));
      expect(rect.width, closeTo(100 * 16 / 9, 0.01));
      expect(rect.center.dx, closeTo(668 / 2, 0.01));
    });

    test('骨架非贴底（横屏编辑面 / 背景位）：同观看态整屏 contain 居中', () {
      expect(rectFor(skeleton: backgroundSkeleton), rectFor(skeleton: null));
    });

    test('竖屏编辑贴底：盒高封顶在未取景画面矩形高（选区更「高」时左右留黑）', () {
      // 真机竖屏基准 361.1×781.7、普通行集：「未取景」带高 = 361.1 ÷ 16/9
      // ≈ 203.12、带顶 ≈ 62.58。选区宽 0.5、高 0.6 → 内容比 ≈ 1.4815。
      const sourceRatio = 16 / 9;
      const selection = FramingSelection(
        left: 0.25,
        top: 0.2,
        right: 0.75,
        bottom: 0.8,
      );
      final skeleton = editorSkeletonFor(
        screen: const Size(361.1, 781.7),
        trackBandHeight: 208,
        videoAspectRatio: sourceRatio,
        framingAspectRatio: selection.contentAspectRatio(sourceRatio),
      );
      final rect = rectFor(
        screen: const Size(361.1, 781.7),
        skeleton: skeleton,
        selection: selection,
      );
      const bandHeight = 203.11875;
      const stageTop = kEditorTopBarHeight + 62.58125;
      expect(rect.height, closeTo(bandHeight, 0.01), reason: '盒高封顶在未取景画面矩形高');
      expect(
        rect.bottom,
        closeTo(stageTop + bandHeight, 0.01),
        reason: '底边贴画面区下缘',
      );
      expect(rect.top, closeTo(stageTop, 0.01), reason: '顶边不上移');
      expect(rect.width, lessThan(361.1), reason: '选区更「高」→ 左右留黑');
      // 显示宽 = 带高 × 内容比 ≈ 203.12 × 1.4815 ≈ 300.9，水平居中。
      expect(
        rect.width,
        closeTo(bandHeight * selection.contentAspectRatio(sourceRatio), 0.05),
      );
      expect(rect.center.dx, closeTo(361.1 / 2, 0.01));
    });

    test('宽高比未知：只有一条兜底——画面即容器，返回可用区本身', () {
      const screen = Size(668, 1368);
      const systemTopInset = 24.0;
      expect(
        rectFor(
          screen: screen,
          systemTopInset: systemTopInset,
          aspectRatio: null,
        ),
        const Rect.fromLTWH(0, 0, 668, 1368),
        reason: '观看态可用区 = 整屏（不扣顶栏内缩）',
      );
      expect(
        rectFor(
          screen: screen,
          systemTopInset: systemTopInset,
          aspectRatio: -1,
        ),
        const Rect.fromLTWH(0, 0, 668, 1368),
        reason: '非正比与 null 同一条兜底',
      );
      expect(
        rectFor(
          screen: screen,
          systemTopInset: systemTopInset,
          aspectRatio: null,
          skeleton: stickSkeleton,
        ),
        const Rect.fromLTWH(0, 24 + kEditorTopBarHeight + 50, 668, 100),
        reason: '贴底分支的可用区 = 画面带',
      );
      expect(
        rectFor(aspectRatio: null, selection: leftHalf),
        const Rect.fromLTWH(0, 0, 800, 600),
        reason: '宽高比未知时选区也套不上窗口，可见范围就是容器',
      );
    });
  });

  group('compareFramingPictureRect（对比源侧取景后的画面矩形）', () {
    test('未调过：与既有半区 contain 画面矩形逐像素一致', () {
      final unframed = compareFramingPictureRect(
        screen: const Size(800, 600),
        landscape: true,
        aspectRatio: 16 / 9,
      );
      expect(unframed.left, closeTo(0, 1e-9));
      expect(unframed.top, closeTo(187.78125, 1e-9));
      expect(unframed.width, closeTo(399, 1e-9));
      expect(unframed.height, closeTo(224.4375, 1e-9));
    });

    test('左半区选区：内容按 contain 放到最大、中心对到半区中心', () {
      final framed = compareFramingPictureRect(
        screen: const Size(800, 600),
        landscape: true,
        aspectRatio: 16 / 9,
        selection: leftHalf,
      );
      expect(framed.left, closeTo(0, 0.01));
      expect(framed.width, closeTo(399, 0.01));
      expect(framed.height, closeTo(448.875, 0.01));
      expect(framed.center.dy, closeTo(300, 0.01));
    });
  });
}
