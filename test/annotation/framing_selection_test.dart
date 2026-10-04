/// 取景选区纯域件直测（收紧手势）：
/// 取景选区值对象、最小边（屏幕 24dp）与合法域、「选区 + 本态几何 → 显示
/// 变换」的 contain 派生（含竖屏贴底分支与画面宽高比未知的退化分支）、
/// **唯一一条**「四边硬钳在整帧内 + 最小边」钳制（建框／整体平移／控制点三
/// 条拖动路径共用）、逐轴自适应控制点命中（`min(48dp, 该轴框长 ÷ 2)`）、单指
/// 拖动会话的基准规则。零框架依赖、不启动 widget 环境。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/framing_selection.dart';

void main() {
  group('① 选区值对象与最小边', () {
    test('四边即取值：宽高与中心由四边推出', () {
      const selection = FramingSelection(
        left: 0.25,
        top: 0.1,
        right: 0.75,
        bottom: 0.6,
      );
      expect(selection.width, closeTo(0.5, 1e-12));
      expect(selection.height, closeTo(0.5, 1e-12));
      expect(selection.centerX, closeTo(0.5, 1e-12));
      expect(selection.centerY, closeTo(0.35, 1e-12));
    });

    test('整帧 = [0, 1] 全取', () {
      const full = FramingSelection.fullFrame();
      expect(full.left, 0);
      expect(full.top, 0);
      expect(full.right, 1);
      expect(full.bottom, 1);
    });

    test('最小边 = 屏幕 24dp 换算到画面坐标系（按画面较短边）', () {
      // 400×225 画面：较短边 225 → 24 / 225 ≈ 0.10667。
      expect(
        framingSelectionMinEdge(pictureWidth: 400, pictureHeight: 225),
        closeTo(24 / 225, 1e-12),
      );
      // 较短边换成竖向：同一量随画面尺寸而变。
      expect(
        framingSelectionMinEdge(pictureWidth: 225, pictureHeight: 400),
        closeTo(24 / 225, 1e-12),
      );
      expect(
        framingSelectionMinEdge(pictureWidth: 800, pictureHeight: 450),
        closeTo(24 / 450, 1e-12),
      );
    });

    test('画面尺寸退化（非正）时最小边安静降级为 0（不报错）', () {
      expect(framingSelectionMinEdge(pictureWidth: 0, pictureHeight: 225), 0);
      expect(framingSelectionMinEdge(pictureWidth: -3, pictureHeight: 0), 0);
    });

    test('建框：不小于最小边才成框', () {
      const enough = FramingSelection(
        left: 0.1,
        top: 0.1,
        right: 0.2,
        bottom: 0.2,
      );
      expect(
        isFramingSelectionLargeEnough(selection: enough, minEdge: 0.05),
        isTrue,
      );
      const tooShort = FramingSelection(
        left: 0.1,
        top: 0.1,
        right: 0.2,
        bottom: 0.12,
      );
      expect(
        isFramingSelectionLargeEnough(selection: tooShort, minEdge: 0.05),
        isFalse,
      );
    });
  });

  // 变换的独立校验模型：画面 contain 在可用区里居中，变换按「绕可用区中心
  // 缩放、再平移」施加；由此把选区的四边映射到可用区坐标。
  ({double left, double top, double right, double bottom}) mappedRect({
    required FramingSelectionTransform t,
    required FramingSelectionGeometry g,
    required FramingSelection selection,
  }) {
    final centerX = g.availableWidth / 2;
    final centerY = g.availableHeight / 2;
    return (
      left:
          centerX +
          t.scale * g.pictureWidth * (selection.left - 0.5) +
          t.translateX,
      top:
          centerY +
          t.scale * g.pictureHeight * (selection.top - 0.5) +
          t.translateY,
      right:
          centerX +
          t.scale * g.pictureWidth * (selection.right - 0.5) +
          t.translateX,
      bottom:
          centerY +
          t.scale * g.pictureHeight * (selection.bottom - 0.5) +
          t.translateY,
    );
  }

  group('② 选区 + 本态几何 → 显示变换（contain）', () {
    // 16:9 画面在 800×450 可用区里恰好占满。
    const fullPath = FramingSelectionGeometry(
      availableWidth: 800,
      availableHeight: 450,
      aspectRatio: 16 / 9,
    );

    test('选区内容按 contain 放到最大且不变形', () {
      const selection = FramingSelection(
        left: 0.25,
        top: 0.25,
        right: 0.75,
        bottom: 0.5,
      );
      final t = framingSelectionTransform(
        selection: selection,
        geometry: fullPath,
      );
      // 选区内容 400×112.5 装进 800×450：宽限 2×、高限 4× → 2×。
      expect(t.scale, closeTo(2, 1e-9));
      final rect = mappedRect(t: t, g: fullPath, selection: selection);
      expect(rect.left, closeTo(0, 1e-9));
      expect(rect.top, closeTo(112.5, 1e-9));
      expect(rect.right, closeTo(800, 1e-9));
      expect(rect.bottom, closeTo(337.5, 1e-9));
      expect(rect.right - rect.left, closeTo(800, 1e-9));
      expect(rect.bottom - rect.top, closeTo(225, 1e-9));
      // 选区中心对到可用区中心。
      expect((rect.left + rect.right) / 2, closeTo(400, 1e-9));
      expect((rect.top + rect.bottom) / 2, closeTo(225, 1e-9));
    });

    test('同一份选区在整屏与半区：各自可见范围都符合 contain', () {
      const selection = FramingSelection(
        left: 0.25,
        top: 0.25,
        right: 0.75,
        bottom: 0.75,
      );
      const halfPane = FramingSelectionGeometry(
        availableWidth: 400,
        availableHeight: 450,
        aspectRatio: 16 / 9,
      );

      final full = framingSelectionTransform(
        selection: selection,
        geometry: fullPath,
      );
      final half = framingSelectionTransform(
        selection: selection,
        geometry: halfPane,
      );

      // 全屏：选区内容 400×225 → contain 后铺满 800×450。
      final fullRect = mappedRect(t: full, g: fullPath, selection: selection);
      expect(fullRect.right - fullRect.left, closeTo(800, 1e-9));
      expect(fullRect.bottom - fullRect.top, closeTo(450, 1e-9));

      // 半区：画面 contain 为 400×225，选区内容 200×112.5 → 装进 400×450
      // 得 400×225（与选区内容同比例，不变形）。
      final halfRect = mappedRect(t: half, g: halfPane, selection: selection);
      expect(halfRect.right - halfRect.left, closeTo(400, 1e-9));
      expect(halfRect.bottom - halfRect.top, closeTo(225, 1e-9));
      expect(halfRect.left, closeTo(0, 1e-9));
      expect(halfRect.top, closeTo(112.5, 1e-9));
    });

    test('未调过（无选区）= 整帧 contain：非贴底分支为恒等', () {
      final t = framingSelectionTransform(selection: null, geometry: fullPath);
      expect(t.scale, 1);
      expect(t.translateX, 0);
      expect(t.translateY, 0);
    });
  });

  group('③ 竖屏贴底分支', () {
    // 竖屏画面区 400×800，16:9 画面 contain 为 400×225。
    const portrait = FramingSelectionGeometry(
      availableWidth: 400,
      availableHeight: 800,
      aspectRatio: 16 / 9,
      sticksToBottom: true,
    );

    test('未调过时与既有 contain 贴底逐像素相同', () {
      final t = framingSelectionTransform(selection: null, geometry: portrait);
      final rect = mappedRect(
        t: t,
        g: portrait,
        selection: const FramingSelection.fullFrame(),
      );
      // 既有贴底：画面带 y ∈ [可用区高 − 画面高, 可用区高]、满宽。
      expect(rect.left, closeTo(0, 1e-9));
      expect(rect.right, closeTo(400, 1e-9));
      expect(rect.top, closeTo(800 - 225, 1e-9));
      expect(rect.bottom, closeTo(800, 1e-9));
    });

    test('选区变窄时内容按比例缩进可用区、下缘贴住可用区下缘', () {
      // 竖长选区（0.2 宽、整高）：内容按高受限缩放，横向缩进并居中。
      const selection = FramingSelection(
        left: 0.4,
        top: 0,
        right: 0.6,
        bottom: 1,
      );
      final t = framingSelectionTransform(
        selection: selection,
        geometry: portrait,
      );
      final rect = mappedRect(t: t, g: portrait, selection: selection);
      expect(rect.right - rect.left, closeTo(80 * (800 / 225), 1e-9));
      expect(rect.right - rect.left, lessThan(400));
      expect((rect.left + rect.right) / 2, closeTo(200, 1e-9));
      expect(rect.bottom, closeTo(800, 1e-9));
      expect(rect.bottom - rect.top, closeTo(800, 1e-9));
    });

    test('选区下缘对到可用区下缘（纵向不再取中心）', () {
      // 居中选区：纵向把下缘对到可用区下缘，内容上缘上移。
      const selection = FramingSelection(
        left: 0.25,
        top: 0.25,
        right: 0.75,
        bottom: 0.5,
      );
      final t = framingSelectionTransform(
        selection: selection,
        geometry: portrait,
      );
      final rect = mappedRect(t: t, g: portrait, selection: selection);
      expect(rect.bottom, closeTo(800, 1e-9));
      // 内容 200×56.25，宽限 2×、高限 800/56.25 → 2× → 400×112.5。
      expect(rect.right - rect.left, closeTo(400, 1e-9));
      expect(rect.bottom - rect.top, closeTo(112.5, 1e-9));
    });
  });

  group('④ 画面宽高比未知（画面即容器）', () {
    const unknown = FramingSelectionGeometry(
      availableWidth: 1280,
      availableHeight: 720,
      aspectRatio: null,
    );

    test('按无变换安静降级、不报错', () {
      final t = framingSelectionTransform(
        selection: const FramingSelection(
          left: 0.2,
          top: 0.2,
          right: 0.6,
          bottom: 0.6,
        ),
        geometry: unknown,
      );
      expect(t.scale, 1);
      expect(t.translateX, 0);
      expect(t.translateY, 0);
    });

    test('几何尺寸退化（非正）同样安静降级为无变换', () {
      const degenerate = FramingSelectionGeometry(
        availableWidth: 0,
        availableHeight: 720,
        aspectRatio: 16 / 9,
      );
      final t = framingSelectionTransform(
        selection: null,
        geometry: degenerate,
      );
      expect(t.scale, 1);
      expect(t.translateX, 0);
    });
  });

  /// 建框路径（纯域入口）。
  FramingSelection diagonal(double x0, double y0, double x1, double y1) =>
      framingSelectionFromDiagonal(x0: x0, y0: y0, x1: x1, y1: y1);

  /// 整体平移路径（纯域入口）。
  FramingSelection translated(
    FramingSelection base, {
    double dx = 0,
    double dy = 0,
    double minEdge = 0.05,
  }) =>
      framingSelectionTranslated(base: base, dx: dx, dy: dy, minEdge: minEdge);

  /// 控制点路径（纯域入口）。
  FramingSelection resized(
    FramingSelection base,
    FramingSelectionHandle handle, {
    double dx = 0,
    double dy = 0,
    double minEdge = 0.05,
  }) => framingSelectionResized(
    base: base,
    handle: handle,
    dx: dx,
    dy: dy,
    minEdge: minEdge,
  );

  group('⑤ 四边硬钳在整帧内 + 最小边（三条路径共用一个算式）', () {
    test('建框：对角矩形越出整帧时取交集、不撑最小边', () {
      expect(
        diagonal(-0.2, -0.1, 1.3, 1.4),
        const FramingSelection.fullFrame(),
      );

      // 太小的框不被撑到最小边——是否成框交给调用侧判。
      final tooSmall = diagonal(0.1, 0.1, 0.12, 0.2);
      expect(tooSmall.width, closeTo(0.02, 1e-12));
      expect(
        isFramingSelectionLargeEnough(selection: tooSmall, minEdge: 0.05),
        isFalse,
      );
    });

    test('建框式橡皮筋：对角两点归一化成一个矩形', () {
      final rubber = diagonal(0.7, 0.8, 0.3, 0.2);
      expect(rubber.left, closeTo(0.3, 1e-12));
      expect(rubber.top, closeTo(0.2, 1e-12));
      expect(rubber.right, closeTo(0.7, 1e-12));
      expect(rubber.bottom, closeTo(0.8, 1e-12));
    });

    test('整体平移贴到边即停：框整体停住、尺寸不变（无越界量）', () {
      const base = FramingSelection(
        left: 0.1,
        top: 0.3,
        right: 0.5,
        bottom: 0.7,
      );
      // 起手基准 + 当帧位移，四边同加：贴到右缘即整体停住。
      final atEdge = translated(base, dx: 1.2);
      expect(atEdge.right, closeTo(1, 1e-12));
      expect(atEdge.left, closeTo(0.6, 1e-12), reason: '宽度原样、框整体停住');
      expect(atEdge.width, closeTo(base.width, 1e-12));
      expect(atEdge.top, closeTo(0.3, 1e-12));
      expect(atEdge.bottom, closeTo(0.7, 1e-12));

      // 继续外拖：仍停在同处，无尺寸记忆可累。
      expect(translated(base, dx: 2.0), atEdge);
    });

    test('整体平移往回拖即随手指回缩', () {
      const base = FramingSelection(
        left: 0.1,
        top: 0.3,
        right: 0.5,
        bottom: 0.7,
      );
      // 同一次手势里从越界处拖回：框立刻跟手（不是先抵消越界量）。
      final back = translated(base, dx: 0.2, dy: 0.1);
      expect(back.left, closeTo(0.3, 1e-12));
      expect(back.top, closeTo(0.4, 1e-12));
      expect(back.right, closeTo(0.7, 1e-12));
      expect(back.bottom, closeTo(0.8, 1e-12));
      // 拖回起手处：原样。
      expect(translated(base), base);
    });

    test('整体平移贴左缘同样整体停住', () {
      const base = FramingSelection(
        left: 0.6,
        top: 0.3,
        right: 1.0,
        bottom: 0.7,
      );
      final atEdge = translated(base, dx: -0.9);
      expect(atEdge.left, 0);
      expect(atEdge.right, closeTo(0.4, 1e-12));
      expect(atEdge.width, closeTo(base.width, 1e-12));
    });

    test('控制点：四角调两轴、四边中点只调那一条边', () {
      const base = FramingSelection(
        left: 0.2,
        top: 0.25,
        right: 0.6,
        bottom: 0.55,
      );
      final topLeft = resized(
        base,
        FramingSelectionHandle.topLeft,
        dx: -0.1,
        dy: -0.1,
      );
      expect(topLeft.left, closeTo(0.1, 1e-12));
      expect(topLeft.top, closeTo(0.15, 1e-12));
      expect(topLeft.right, closeTo(0.6, 1e-12));
      expect(topLeft.bottom, closeTo(0.55, 1e-12));

      final right = resized(base, FramingSelectionHandle.right, dx: 0.2, dy: 9);
      expect(right.right, closeTo(0.8, 1e-12));
      expect(right.left, closeTo(0.2, 1e-12));
      expect(right.top, closeTo(0.25, 1e-12));
      expect(right.bottom, closeTo(0.55, 1e-12));
    });

    test('控制点贴边外拖：该边停在整帧缘、往回拖跟手', () {
      const base = FramingSelection(
        left: 0.2,
        top: 0.25,
        right: 0.6,
        bottom: 0.55,
      );
      final atEdge = resized(base, FramingSelectionHandle.right, dx: 1.0);
      expect(atEdge.right, closeTo(1, 1e-12));
      expect(atEdge.left, closeTo(0.2, 1e-12));

      final back = resized(base, FramingSelectionHandle.right, dx: 0.1);
      expect(back.right, closeTo(0.7, 1e-12), reason: '往回拖立刻跟手');
    });

    test('控制点收缩不足最小边：被拖的边让位、对侧不动', () {
      const target = FramingSelection(
        left: 0.2,
        top: 0.2,
        right: 0.4,
        bottom: 0.4,
      );
      // 上边中点下拖到越过下缘：上缘停在下缘之上一个最小边，下缘不动。
      final resolved = resized(target, FramingSelectionHandle.top, dy: 0.25);
      expect(resolved.bottom, closeTo(0.4, 1e-12));
      expect(resolved.top, closeTo(0.35, 1e-12));
      expect(resolved.left, closeTo(0.2, 1e-12));
      expect(resolved.right, closeTo(0.4, 1e-12));

      // 左边中点右拖：右缘不动、左缘停在最小边处。
      final narrowed = resized(target, FramingSelectionHandle.left, dx: 0.25);
      expect(narrowed.right, closeTo(0.4, 1e-12));
      expect(narrowed.left, closeTo(0.35, 1e-12));
      expect(narrowed.top, closeTo(0.2, 1e-12));
      expect(narrowed.bottom, closeTo(0.4, 1e-12));
    });

    test('控制点收缩跨过中线也不跳变：对侧边始终不动', () {
      const target = FramingSelection(
        left: 0.3,
        top: 0.3,
        right: 0.5,
        bottom: 0.5,
      );
      for (final dy in [0.2, 0.21, 0.4]) {
        final resolved = resized(target, FramingSelectionHandle.top, dy: dy);
        expect(resolved.bottom, closeTo(0.5, 1e-12));
        expect(resolved.top, closeTo(0.45, 1e-12));
      }
    });

    test('三条路径共用同一钳制：越界都落回整帧、不小于最小边', () {
      const base = FramingSelection(
        left: 0.2,
        top: 0.2,
        right: 0.4,
        bottom: 0.4,
      );
      final paths = [
        diagonal(-1, -1, 2, 2),
        translated(base, dx: 5, dy: 5),
        resized(base, FramingSelectionHandle.bottomRight, dx: 5, dy: 5),
      ];
      for (final r in paths) {
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(1));
        expect(r.bottom, lessThanOrEqualTo(1));
      }
      expect(paths[0], const FramingSelection.fullFrame());
      expect(paths[1].right, 1);
      expect(paths[1].bottom, 1);
      expect(paths[2].right, 1);
      expect(paths[2].bottom, 1);
    });

    test('最小边在整屏与半区各自换算（阈值随画面尺寸而变）', () {
      // 短边 269.4375 的半区：24 / 269.4375 ≈ 0.08907。
      final half = framingSelectionMinEdge(
        pictureWidth: 479,
        pictureHeight: 269.4375,
      );
      expect(half, closeTo(24 / 269.4375, 1e-12));
      // 整屏短边 361.1：24 / 361.1 ≈ 0.06646。
      final full = framingSelectionMinEdge(
        pictureWidth: 642,
        pictureHeight: 361.1,
      );
      expect(full, closeTo(24 / 361.1, 1e-12));
      expect(full, lessThan(half));
    });
  });

  group('⑥ 单指拖动会话基准规则', () {
    const committed = FramingSelection(
      left: 0.2,
      top: 0.3,
      right: 0.6,
      bottom: 0.7,
    );

    FramingSelectionGestureSession session({
      FramingSelectionGestureSession? current,
      FramingSelection? base,
      double focalX = 0,
      double focalY = 0,
      int pointerCount = 1,
      bool recognizerRestarted = false,
    }) => resolveFramingSelectionGestureSession(
      current: current,
      committed: base,
      focalX: focalX,
      focalY: focalY,
      pointerCount: pointerCount,
      recognizerRestarted: recognizerRestarted,
    );

    test('起手取基准：尚无会话 → 基准 = 已提交选区、焦点 = 落点', () {
      final first = session(base: committed, focalX: 120, focalY: 300);
      expect(first.base, committed);
      expect(first.focalX, 120);
      expect(first.focalY, 300);
      expect(first.pointerCount, 1);
    });

    test('识别器重启 → 重设基准，会话延续', () {
      const later = FramingSelection(
        left: 0.1,
        top: 0.1,
        right: 0.4,
        bottom: 0.5,
      );
      final first = session(base: committed, focalX: 100, focalY: 100);
      final restarted = session(
        current: first,
        base: later,
        focalX: 200,
        focalY: 300,
        recognizerRestarted: true,
      );
      expect(restarted.base, later);
      expect(restarted.focalX, 200);
      expect(restarted.focalY, 300);
    });

    test('手指数变化 → 重设基准', () {
      final first = session(base: committed, focalX: 100, focalY: 100);
      final restarted = session(
        current: first,
        base: committed,
        focalX: 150,
        focalY: 250,
        pointerCount: 2,
      );
      expect(restarted.pointerCount, 2);
      expect(restarted.focalX, 150);
      expect(restarted.base, committed);
    });

    test('普通更新帧：基准、焦点与手指数都不动', () {
      final first = session(base: committed, focalX: 100, focalY: 100);
      final updated = session(
        current: first,
        base: committed,
        focalX: 180,
        focalY: 260,
      );
      expect(updated, first);
    });

    test('未调过（无已提交选区）也能起手取基准', () {
      final first = session(focalX: 50, focalY: 60);
      expect(first.base, isNull);
      expect(first.focalX, 50);
    });
  });

  group('⑦ 选区在画面矩形内的映射', () {
    test('四边按画面矩形线性映射（唯一一处归一化）', () {
      const selection = FramingSelection(
        left: 0.25,
        top: 0.1,
        right: 0.75,
        bottom: 0.6,
      );
      final rect = framingSelectionRectOnPicture(
        selection: selection,
        pictureLeft: 100,
        pictureTop: 40,
        pictureWidth: 400,
        pictureHeight: 300,
      );

      expect(rect.left, closeTo(200, 1e-9));
      expect(rect.top, closeTo(70, 1e-9));
      expect(rect.right, closeTo(400, 1e-9));
      expect(rect.bottom, closeTo(220, 1e-9));
    });
  });

  group('⑧ 取景控制点的中心与逐轴自适应命中', () {
    // 选区四边在画面矩形 (100, 40, 400 × 300) 内映射为
    // L=200 T=70 R=400 B=220（四角四点、四边中点 (300,70)/(400,145)/(300,220)/(200,145)）。
    const selection = FramingSelection(
      left: 0.25,
      top: 0.1,
      right: 0.75,
      bottom: 0.6,
    );

    List<({FramingSelectionHandle handle, double x, double y})> centers() =>
        framingSelectionHandleCenters(
          selection: selection,
          pictureLeft: 100,
          pictureTop: 40,
          pictureWidth: 400,
          pictureHeight: 300,
        );

    FramingSelectionHandle? hitAt(
      double x,
      double y, {
      FramingSelection target = selection,
      double maxHitSize = 48,
    }) => framingSelectionHandleAt(
      selection: target,
      pictureLeft: 100,
      pictureTop: 40,
      pictureWidth: 400,
      pictureHeight: 300,
      x: x,
      y: y,
      maxHitSize: maxHitSize,
    );

    test('八个控制点：四角取矩形四角、四边中点取四边中点', () {
      final points = centers();
      expect(points, hasLength(8), reason: '四角 + 四边中点');

      final byHandle = {
        for (final center in points) center.handle: (center.x, center.y),
      };
      expect(byHandle[FramingSelectionHandle.topLeft], (200.0, 70.0));
      expect(byHandle[FramingSelectionHandle.topRight], (400.0, 70.0));
      expect(byHandle[FramingSelectionHandle.bottomRight], (400.0, 220.0));
      expect(byHandle[FramingSelectionHandle.bottomLeft], (200.0, 220.0));
      expect(byHandle[FramingSelectionHandle.top], (300.0, 70.0));
      expect(byHandle[FramingSelectionHandle.right], (400.0, 145.0));
      expect(byHandle[FramingSelectionHandle.bottom], (300.0, 220.0));
      expect(byHandle[FramingSelectionHandle.left], (200.0, 145.0));
    });

    test('命中盒按手指尺寸给足：框够大时控制点中心 ±24dp 内命中', () {
      expect(hitAt(200, 70), FramingSelectionHandle.topLeft);
      expect(hitAt(200 + 23, 70 + 23), FramingSelectionHandle.topLeft);
      expect(hitAt(400 - 5, 220), FramingSelectionHandle.bottomRight);
      expect(hitAt(200, 145 + 20), FramingSelectionHandle.left);
    });

    test('命中盒以外不命中：边线本体不是控制点', () {
      // 上边线 1/4 处（300 与 200 的中点 250）离两个上缘控制点各 50dp。
      expect(hitAt(250, 70), isNull);
      // 框中心：不在任何控制点上。
      expect(hitAt(300, 145), isNull);
      // 超出命中盒（>24dp）。
      expect(hitAt(300, 70 + 25), isNull);
    });

    test('短边 < 96dp 时命中盒随框收缩：中央恒留可整体平移的空带', () {
      // 画面矩形内 40×40 的框：(300,190)-(340,230)；命中盒边长
      // min(48, 40 ÷ 2) = 20 → 半径 10。
      const tiny = FramingSelection(
        left: 0.5,
        top: 0.5,
        right: 0.6,
        bottom: 0.5 + 40 / 300,
      );
      // 框中心 (320, 210)：距四角与四边中点都 >10dp → 不命中（可整体平移）。
      expect(hitAt(320, 210, target: tiny), isNull);
      // 距角点 (300,190) 两轴各 11dp：超出收缩后的命中盒（固定 48dp 会误命中）。
      expect(hitAt(300 + 11, 190 + 11, target: tiny), isNull);
      // 距角点 9dp：收缩后仍命中角点。
      expect(hitAt(300 + 9, 190, target: tiny), FramingSelectionHandle.topLeft);
    });

    test('命中盒逐轴独立：宽框的竖向命中盒随短边收缩', () {
      // 画面矩形内 200×40 的框：(100,190)-(300,230)；命中盒宽
      // min(48, 100) = 48 → 半径 24，高 min(48, 20) = 20 → 半径 10。
      const wide = FramingSelection(
        left: 0,
        top: 0.5,
        right: 0.5,
        bottom: 0.5 + 40 / 300,
      );
      // 上边中点 (200,190) 下方 11dp：竖向命中盒随短边收缩、不命中（固定 48
      // 会命中）；下方 9dp 内命中。
      expect(hitAt(200, 190 + 11, target: wide), isNull);
      expect(hitAt(200, 190 + 9, target: wide), FramingSelectionHandle.top);
    });

    test('命中盒上限 48dp：框足够大时不放大', () {
      expect(hitAt(200 + 24, 70), FramingSelectionHandle.topLeft);
      expect(hitAt(200 + 25, 70), isNull);
    });

    test('控制点命中盒相触处四角优先于四边中点', () {
      // 画面矩形内 48×48 的框：(300,190)-(348,238)；命中盒边长
      // min(48, 24) = 24 → 半径 12。角点 (300,190) 与上边中点 (324,190) 的
      // 命中盒在 x=312 相触：按四角。
      const tiny = FramingSelection(
        left: 0.5,
        top: 0.5,
        right: 0.5 + 48 / 400,
        bottom: 0.5 + 48 / 300,
      );
      expect(
        hitAt(300 + 12, 190, target: tiny),
        FramingSelectionHandle.topLeft,
      );
      expect(hitAt(300, 190, target: tiny), FramingSelectionHandle.topLeft);
      // 越过相触点到上边中点一侧：命中上边中点。
      expect(hitAt(300 + 13, 190, target: tiny), FramingSelectionHandle.top);
    });
  });

  group('⑨ 选区内容宽高比（内容像素比 = 归一化宽高比 × 源比）', () {
    test('半宽半高选区不改内容比例；压扁/拉高按归一化比乘源比', () {
      const half = FramingSelection(
        left: 0.25,
        top: 0.25,
        right: 0.75,
        bottom: 0.75,
      );
      expect(half.contentAspectRatio(16 / 9), closeTo(16 / 9, 1e-9));

      // 左半区（宽 0.5、高 1）：内容宽高比 = 源比减半。
      const leftHalf = FramingSelection(left: 0, top: 0, right: 0.5, bottom: 1);
      expect(leftHalf.contentAspectRatio(2), closeTo(1, 1e-9));

      // 上半区（宽 1、高 0.5）：内容宽高比 = 源比翻倍。
      const topHalf = FramingSelection(left: 0, top: 0, right: 1, bottom: 0.5);
      expect(topHalf.contentAspectRatio(2), closeTo(4, 1e-9));
    });
  });
}
