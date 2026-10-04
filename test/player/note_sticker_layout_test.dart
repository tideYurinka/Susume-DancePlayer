import 'package:dance_learning_app/annotation/framing_selection.dart'
    show FramingSelection;
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/player/note_sticker_layout.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('贴纸窗内显隐谓词（播放头 ∈ 时间窗，与播放/暂停无关）', () {
    const note = NoteSticker(startMs: 1000, endMs: 5000, text: '这里注意手');

    test('播放头落在窗内（含起点）→ 显示', () {
      expect(noteStickerAt([note], 1000), same(note));
      expect(noteStickerAt([note], 3000), same(note));
    });

    test('播放头落在窗外（终点不含、起点之前）→ 消失', () {
      expect(noteStickerAt([note], 5000), isNull);
      expect(noteStickerAt([note], 999), isNull);
    });

    test('无备注 → 消失', () {
      expect(noteStickerAt(const [], 3000), isNull);
    });

    test('异常输入（乱序/重叠）优雅降级：取命中的一条、不崩', () {
      const late = NoteSticker(startMs: 4000, endMs: 6000);
      final unordered = [late, note]; // 乱序 + 重叠（坏文件）。
      expect(noteStickerAt(unordered, 4500), same(late));
      expect(noteStickerAt(unordered, 2000), same(note));
    });
  });

  group('贴纸像素矩形（几何按视频内容矩形归一化 → 像素 + 钳制）', () {
    const contentRect = Rect.fromLTWH(100, 200, 800, 600);

    test('默认落点：水平居中、自顶边下移 12%、按实际尺寸换算成像素矩形', () {
      // 默认落点来自具名常量（真机看版项），独立真值 = 常量本身。
      final rect = noteStickerRect(
        geometry: const NoteGeometry(),
        contentRect: contentRect,
        stickerSize: const Size(200, 40),
        faceDirection: FaceDirection.original,
      );
      expect(rect.center.dx, 100 + 800 * noteDefaultCenterX);
      expect(rect.center.dy, 200 + 600 * noteDefaultCenterY);
      expect(rect.size, const Size(200, 40));
    });

    test('几何系数换算：位置取中心归一化，尺寸随等比系数放大', () {
      final rect = noteStickerRect(
        geometry: const NoteGeometry(centerX: 0.25, centerY: 0.5, scale: 2),
        contentRect: contentRect,
        stickerSize: const Size(100, 20),
        faceDirection: FaceDirection.original,
      );
      expect(rect.center, const Offset(100 + 200, 200 + 300));
      expect(rect.size, const Size(200, 40));
    });

    test('创建时按实际尺寸钳进内容矩形：贴纸完整留在内容矩形内', () {
      // 中心被顶边 12% 落点 + 过大贴纸推出上缘 → 钳回框内。
      final rect = noteStickerRect(
        geometry: const NoteGeometry(),
        contentRect: contentRect,
        stickerSize: const Size(200, 400),
        faceDirection: FaceDirection.original,
      );
      expect(
        rect.top >= contentRect.top &&
            rect.bottom <= contentRect.bottom &&
            rect.left >= contentRect.left &&
            rect.right <= contentRect.right,
        isTrue,
        reason: '贴纸矩形被钳进视频内容矩形',
      );
    });

    test('贴纸大于内容矩形：居中放置、不溢出（钳制退化为居中）', () {
      final rect = noteStickerRect(
        geometry: const NoteGeometry(centerX: 0.9, centerY: 0.9),
        contentRect: contentRect,
        stickerSize: const Size(1600, 1200),
        faceDirection: FaceDirection.original,
      );
      expect(rect.center, contentRect.center);
      expect(rect.size, const Size(1600, 1200), reason: '尺寸原样、不缩放');
    });
  });

  group('贴纸随面换算（注解层按面方向做水平坐标换算）', () {
    const contentRect = Rect.fromLTWH(100, 200, 800, 600);
    const geometry = NoteGeometry(centerX: 0.25, centerY: 0.4);
    const stickerSize = Size(100, 20);

    test('原相：归一化中心按内容矩形原样映射（水平不取反）', () {
      expect(
        noteStickerCenterOnFace(
          center: const Offset(0.25, 0.4),
          faceDirection: FaceDirection.original,
        ),
        const Offset(0.25, 0.4),
      );
    });

    test('镜像：水平分量按「到框边的距离」取反，纵向不动', () {
      expect(
        noteStickerCenterOnFace(
          center: const Offset(0.25, 0.4),
          faceDirection: FaceDirection.mirrored,
        ),
        const Offset(0.75, 0.4),
      );
    });

    test('像素矩形按面换算：同一归一化几何镜像后落在对侧等距处', () {
      final original = noteStickerRect(
        geometry: geometry,
        contentRect: contentRect,
        stickerSize: stickerSize,
        faceDirection: FaceDirection.original,
      );
      final mirrored = noteStickerRect(
        geometry: geometry,
        contentRect: contentRect,
        stickerSize: stickerSize,
        faceDirection: FaceDirection.mirrored,
      );
      // 独立真值：镜像落点 = 内容矩形左右镜像（0.25 → 0.75）。
      expect(original.center.dx, 100 + 800 * 0.25);
      expect(mirrored.center.dx, 100 + 800 * 0.75);
      expect(
        original.center.dx - contentRect.left,
        closeTo(contentRect.right - mirrored.center.dx, 1e-9),
        reason: '镜像后到左右框边的距离互换',
      );
      expect(mirrored.center.dy, original.center.dy, reason: '纵向不参与换算');
      expect(mirrored.size, original.size, reason: '尺寸不参与换算');
    });

    test('镜像两态下贴纸矩形都完整钳进内容矩形', () {
      for (final direction in FaceDirection.values) {
        final rect = noteStickerRect(
          geometry: const NoteGeometry(centerX: 0.02, centerY: 0.98, scale: 3),
          contentRect: contentRect,
          stickerSize: stickerSize,
          faceDirection: direction,
        );
        expect(
          rect.left >= contentRect.left &&
              rect.right <= contentRect.right &&
              rect.top >= contentRect.top &&
              rect.bottom <= contentRect.bottom,
          isTrue,
          reason: '$direction 下贴纸矩形仍完整留在内容矩形内',
        );
      }
    });
  });

  group('贴纸手势换算（屏幕像素 ↔ 归一化几何，会话内单点）', () {
    const contentRect = Rect.fromLTWH(0, 0, 800, 600);
    const start = NoteGeometry(centerX: 0.5, centerY: 0.12, scale: 1);

    test('单指平移（原相）：像素增量按内容矩形换算为归一化中心增量', () {
      final translated = noteGeometryFromGesture(
        start: start,
        contentRect: contentRect,
        panDelta: const Offset(80, 60),
        pinchRatio: 1,
        faceDirection: FaceDirection.original,
      );
      expect(translated.centerX, closeTo(0.6, 1e-9));
      expect(translated.centerY, closeTo(0.22, 1e-9));
      expect(translated.scale, 1);
      // 内容矩形偏移不影响归一化换算（参考系 = 内容矩形）。
      final shifted = noteGeometryFromGesture(
        start: start,
        contentRect: const Rect.fromLTWH(40, 90, 800, 600),
        panDelta: const Offset(-80, -60),
        pinchRatio: 1,
        faceDirection: FaceDirection.original,
      );
      expect(shifted.centerX, closeTo(0.4, 1e-9));
      expect(shifted.centerY, closeTo(0.02, 1e-9));
    });

    test('单指平移（镜像）：水平增量反相（屏幕向右 = 归一化 x 减小）', () {
      final translated = noteGeometryFromGesture(
        start: start,
        contentRect: contentRect,
        panDelta: const Offset(80, 60),
        pinchRatio: 1,
        faceDirection: FaceDirection.mirrored,
      );
      // 渲染换算为 x → 1 − x：屏幕向右的 80px 必须让 x 减小，贴纸才跟着
      // 手指向右（而不是反着走）；纵向不参与换算。
      expect(translated.centerX, closeTo(0.4, 1e-9));
      expect(translated.centerY, closeTo(0.22, 1e-9));
      expect(translated.scale, 1);
    });

    test('双指捏合：等比系数按倍率缩放（字号随整体缩放承担）', () {
      expect(
        noteGeometryFromGesture(
          start: start,
          contentRect: contentRect,
          panDelta: Offset.zero,
          pinchRatio: 1.5,
          faceDirection: FaceDirection.original,
        ),
        const NoteGeometry(centerX: 0.5, centerY: 0.12, scale: 1.5),
      );
    });

    test('空内容矩形：原样返回（无参考系可换算，不崩）', () {
      expect(
        noteGeometryFromGesture(
          start: start,
          contentRect: Rect.zero,
          panDelta: const Offset(80, 60),
          pinchRatio: 2,
          faceDirection: FaceDirection.mirrored,
        ),
        start,
      );
    });
  });

  group('贴纸按取景选区落位', () {
    // 取景后的画面矩形（选定内容上屏后的屏幕矩形）与选区窗口。
    const framedRect = Rect.fromLTWH(100, 200, 400, 300);
    const window = FramingSelection(
      left: 0.25,
      top: 0.25,
      right: 0.75,
      bottom: 0.75,
    );

    test('源点先按选区窗口换算再映射：窗口中心落到画面矩形中心', () {
      final rect = noteStickerRect(
        geometry: const NoteGeometry(centerX: 0.5, centerY: 0.5),
        contentRect: framedRect,
        stickerSize: const Size(40, 20),
        faceDirection: FaceDirection.original,
        selection: window,
      );
      expect(rect.center, framedRect.center);
    });

    test('钉住内容：源点 = 窗口原点 → 画面矩形左上角；源点 = 窗口右下 → 右下角', () {
      Rect at(double x, double y) => noteStickerRect(
        geometry: NoteGeometry(centerX: x, centerY: y),
        contentRect: framedRect,
        stickerSize: const Size(40, 20),
        faceDirection: FaceDirection.original,
        selection: window,
      );
      expect(
        at(0.25, 0.25).center,
        const Offset(120, 210),
        reason: '左上角内缩半个贴纸',
      );
      expect(
        at(0.75, 0.75).center,
        const Offset(480, 490),
        reason: '右下角内缩半个贴纸',
      );
    });

    test('窗口换算在随面换算之前套：镜像把窗口内的横向分量取反', () {
      // 源 x = 0.25 → 窗口 x = 0 → 镜像 → 1（窗口右缘）→ 画面矩形右缘内缩。
      final rect = noteStickerRect(
        geometry: const NoteGeometry(centerX: 0.25, centerY: 0.5),
        contentRect: framedRect,
        stickerSize: const Size(40, 20),
        faceDirection: FaceDirection.mirrored,
        selection: window,
      );
      expect(rect.center, const Offset(480, 350));
    });

    test('标的源点被取景裁掉时钳在画面边缘、不隐藏', () {
      final rect = noteStickerRect(
        geometry: const NoteGeometry(centerX: 0.05, centerY: 0.5),
        contentRect: framedRect,
        stickerSize: const Size(40, 20),
        faceDirection: FaceDirection.original,
        selection: window,
      );
      expect(rect.center.dx, closeTo(framedRect.left + 20, 1e-9));
      expect(rect.center.dy, closeTo(framedRect.center.dy, 1e-9));
    });

    test('屏幕尺寸不随取景缩放：尺寸只吃几何系数', () {
      final framed = noteStickerRect(
        geometry: const NoteGeometry(centerX: 0.5, centerY: 0.5, scale: 2),
        contentRect: framedRect,
        stickerSize: const Size(100, 20),
        faceDirection: FaceDirection.original,
        selection: window,
      );
      expect(framed.size, const Size(200, 40));
    });

    test('未调过（selection = null）与改动前逐像素一致', () {
      for (final direction in FaceDirection.values) {
        final withNull = noteStickerRect(
          geometry: const NoteGeometry(centerX: 0.3, centerY: 0.7, scale: 1.5),
          contentRect: framedRect,
          stickerSize: const Size(100, 20),
          faceDirection: direction,
        );
        final explicitNull = noteStickerRect(
          geometry: const NoteGeometry(centerX: 0.3, centerY: 0.7, scale: 1.5),
          contentRect: framedRect,
          stickerSize: const Size(100, 20),
          faceDirection: direction,
          selection: null,
        );
        expect(withNull, explicitNull);
      }
    });

    test('手势换算取窗口换算的逆：屏幕位移先除画面矩形再乘窗口尺寸', () {
      const start = NoteGeometry(centerX: 0.5, centerY: 0.5, scale: 1);
      final framed = noteGeometryFromGesture(
        start: start,
        contentRect: framedRect,
        panDelta: const Offset(40, 30),
        pinchRatio: 1,
        faceDirection: FaceDirection.original,
        selection: window,
      );
      // dx = 40 / 400 × 窗口宽 0.5 = 0.05；dy = 30 / 300 × 窗口高 0.5 = 0.05。
      expect(framed.centerX, closeTo(0.55, 1e-9));
      expect(framed.centerY, closeTo(0.55, 1e-9));

      // 未调过：除以内容矩形本身（与改动前一致）。
      final unframed = noteGeometryFromGesture(
        start: start,
        contentRect: framedRect,
        panDelta: const Offset(40, 30),
        pinchRatio: 1,
        faceDirection: FaceDirection.original,
      );
      expect(unframed.centerX, closeTo(0.6, 1e-9));
      expect(unframed.centerY, closeTo(0.6, 1e-9));
    });
  });

  group('窗内备注索引（贴纸几何命令的定位依据）', () {
    const note = NoteSticker(startMs: 1000, endMs: 5000);

    test('窗内 → 命中索引；窗外 / 空 → null', () {
      expect(noteStickerIndexAt([note], 3000), 0);
      expect(noteStickerIndexAt([note], 5000), isNull);
      expect(noteStickerIndexAt(const [], 3000), isNull);
    });
  });
}
