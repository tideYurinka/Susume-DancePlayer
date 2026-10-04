/// 单画面取景几何直测：未调过的画面矩形（点画面外退出判定与落点换算的
/// 分母）与**取景后**的画面矩形（下游读数共用的那唯一一份几何）。
/// 零 widget 环境、纯输入输出。
library;

import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/player/compare_framing_view.dart';
import 'package:dance_learning_app/player/editor_skeleton.dart';
import 'package:dance_learning_app/player/framing_stage.dart';
import 'package:flutter/rendering.dart' show Rect;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 竖屏编辑面贴底骨架（与画面件/注解层消费的同一份带几何：带 100、
  /// 带顶 50、画面区 200）。
  const stickSkeleton = EditorSkeleton(
    compact: false,
    portrait: true,
    pictureAreaHeight: 200,
    picturePlacement: PicturePlacement.stickToBottom,
    pictureBandHeight: 100,
    pictureBandTop: 50,
  );

  group('singlePicturePictureRectOnScreen（未调过的画面矩形）', () {
    test('贴底分支：屏幕矩形 = 顶栏之下 + 骨架带顶，尺寸 = 带盒', () {
      final rect = singlePicturePictureRectOnScreen(
        screen: const Size(668, 1368),
        systemTopInset: 24,
        skeleton: stickSkeleton,
        aspectRatio: 16 / 9,
      );
      expect(rect, const Rect.fromLTWH(0, 24 + 52 + 50, 668, 100));
    });

    test('观看态：屏幕矩形 = 整屏 contain 居中（宽限高）', () {
      final rect = singlePicturePictureRectOnScreen(
        screen: const Size(668, 1368),
        systemTopInset: 24,
        skeleton: null,
        aspectRatio: 16 / 9,
      );
      expect(rect!.top, closeTo((1368 - 375.75) / 2, 0.1));
      expect(rect.width, 668);
      expect(rect.height, closeTo(375.75, 0.1));
    });

    test('高限宽（竖向源在竖屏放不下时）：左右留黑、垂直充满', () {
      final rect = singlePicturePictureRectOnScreen(
        screen: const Size(400, 800),
        systemTopInset: 0,
        skeleton: null,
        aspectRatio: 0.4,
      );
      expect(rect!.width, closeTo(800 * 0.4, 0.1));
      expect(rect.left, closeTo((400 - 320) / 2, 0.1));
      expect(rect.top, 0);
      expect(rect.height, 800);
    });

    test('宽高比未知：退化分支返回 null（无「画面外」可达）', () {
      expect(
        singlePicturePictureRectOnScreen(
          screen: const Size(668, 1368),
          systemTopInset: 0,
          skeleton: null,
          aspectRatio: null,
        ),
        isNull,
      );
    });
  });

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

  group('singlePictureFramedPictureRectOnScreen（取景后的单画面矩形）', () {
    test('观看态未调过：整屏 contain 居中（与未取景同一份）', () {
      final framed = singlePictureFramedPictureRectOnScreen(
        screen: const Size(800, 600),
        systemTopInset: 0,
        skeleton: null,
        aspectRatio: 16 / 9,
        selection: null,
      );
      expect(framed, const Rect.fromLTWH(0, 75, 800, 450));
    });

    test('观看态左半区选区：内容高充满、左右留黑', () {
      final framed = singlePictureFramedPictureRectOnScreen(
        screen: const Size(800, 600),
        systemTopInset: 0,
        skeleton: null,
        aspectRatio: 16 / 9,
        selection: leftHalf,
      );
      expect(framed!.left, closeTo(133.333, 0.01));
      expect(framed.width, closeTo(533.333, 0.01));
      expect(framed.height, closeTo(600, 0.01));
    });

    test('宽高比未知：null（与未取景退化分支一致）', () {
      expect(
        singlePictureFramedPictureRectOnScreen(
          screen: const Size(800, 600),
          systemTopInset: 0,
          skeleton: null,
          aspectRatio: null,
          selection: leftHalf,
        ),
        isNull,
      );
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
      final framed = singlePictureFramedPictureRectOnScreen(
        screen: const Size(361.1, 781.7),
        systemTopInset: 0,
        skeleton: skeleton,
        aspectRatio: sourceRatio,
        selection: selection,
      )!;
      const bandHeight = 203.11875;
      const stageTop = kEditorTopBarHeight + 62.58125;
      expect(framed.height, closeTo(bandHeight, 0.01), reason: '盒高封顶在未取景画面矩形高');
      expect(
        framed.bottom,
        closeTo(stageTop + bandHeight, 0.01),
        reason: '底边贴画面区下缘',
      );
      expect(framed.top, closeTo(stageTop, 0.01), reason: '顶边不上移');
      expect(framed.width, lessThan(361.1), reason: '选区更「高」→ 左右留黑');
      // 显示宽 = 带高 × 内容比 ≈ 203.12 × 1.4815 ≈ 300.9，水平居中。
      expect(
        framed.width,
        closeTo(bandHeight * selection.contentAspectRatio(sourceRatio), 0.05),
      );
      expect(framed.center.dx, closeTo(361.1 / 2, 0.01));
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
