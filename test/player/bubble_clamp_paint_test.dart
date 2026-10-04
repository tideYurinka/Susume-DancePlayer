import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:dance_learning_app/player/metronome_settings_store.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 气泡钳位平移的「画点一致」回归：**绘制位置必须与命中位置同一处**。
///
/// 为什么只能看像素：命中与几何查询（`getRect` / `localToGlobal`）都读钳位
/// 平移量的**当前值**，气泡的绘制走 `paint()` 的偏移——两者一旦不同步，
/// 纯几何断言与既有的「命中可达」断言（同样基于 `localToGlobal`）都看不
/// 出来，只有真正画出来的像素能作证。用户侧症状正是它：看得见的按钮点不动
/// （点按穿过气泡落到遮罩上，气泡直接收起）。
///
/// 复现路径 = 生产路径：锚点与真机竖屏同位置；先开较高的节拍提示气泡
/// （钳位值 ≠ 0），再切到较矮的节拍倍频气泡（钳位值回到 0）——钳位值在
/// 首帧量测后变化，正是本回归要钉住的时机。
void main() {
  /// 宽取 compact 档竖屏 361.1dp；高度收窄到 650dp——刻意收窄的**合成档**
  /// （实际逻辑尺寸 361.1 × 650dp，非设备基准），使节拍提示气泡需要竖直钳位、
  /// 倍频气泡不需要（真机上两者高度差更大的同型情形）。
  const logicalSize = Size(1264 / 3.5, 650);

  /// 真机竖屏「节拍提示」工具图标位置（1264×2736 @3.5 实测）。
  const entryCenterX = 88.3;
  const entryBottom = 438.0;
  const entrySize = Size(47.4, 44.6);

  /// 栅格化后逐行统计近黑像素（气泡底 = 0.94 黑叠白底，连同 Material 阴影
  /// 一起落进阈值内），返回「气泡带」的像素行区间。
  ({int top, int bottom}) paintedBubbleBand(ByteData pixels, int width) {
    var top = -1;
    var bottom = -1;
    for (var y = 0; y < pixels.lengthInBytes ~/ (width * 4); y++) {
      var dark = 0;
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        if (pixels.getUint8(i) < 40 &&
            pixels.getUint8(i + 1) < 40 &&
            pixels.getUint8(i + 2) < 40) {
          dark++;
        }
      }
      if (dark > width * 0.5) {
        if (top < 0) top = y;
        bottom = y;
      }
    }
    return (top: top, bottom: bottom);
  }

  testWidgets('钳位值变化后：气泡绘制位置跟随命中位置（看得见的地方点得动）', (tester) async {
    final link = LayerLink();
    tester.view.physicalSize = Size(
      logicalSize.width * 3.5,
      logicalSize.height * 3.5,
    );
    tester.view.devicePixelRatio = 3.5;
    addTearDown(tester.view.reset);

    final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metronomeSettingsAutoRestoreProvider.overrideWithValue(false),
          playbackEngineProvider.overrideWithValue(engine),
        ],
        child: MaterialApp(
          home: RepaintBoundary(
            key: const Key('clamp_paint_probe'),
            child: Scaffold(
              // 纯白底：气泡（近黑）+ 阴影即最暗的一块，便于逐行判带。
              backgroundColor: Colors.white,
              body: Builder(
                builder: (context) {
                  container = ProviderScope.containerOf(context);
                  return Stack(
                    children: [
                      Positioned(
                        left: entryCenterX - entrySize.width / 2,
                        top: entryBottom - entrySize.height,
                        child: CompositedTransformTarget(
                          link: link,
                          child: SizedBox(
                            width: entrySize.width,
                            height: entrySize.height,
                          ),
                        ),
                      ),
                      SpeedBubbleHost(
                        linkFor: (_) => link,
                        targetAnchor: Alignment.bottomCenter,
                        followerAnchor: Alignment.topCenter,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    container
        .read(beatTrackStateProvider.notifier)
        .replace(
          BeatTrackState.ready(
            BeatGrid(
              model: 'fake.onnx',
              fps: 100,
              generatedAt: DateTime.utc(2026, 9, 18),
              beats: const [
                BeatPoint(t: 0.5, down: true),
                BeatPoint(t: 1.0, down: false),
                BeatPoint(t: 1.5, down: false),
                BeatPoint(t: 2.0, down: false),
              ],
            ),
          ),
        );

    // 先开节拍提示气泡（高、需竖直钳位），再切节拍倍频气泡（矮、钳位回 0）。
    container
        .read(speedBubbleSessionProvider.notifier)
        .open(SpeedBubbleMode.beat);
    await tester.pumpAndSettle();
    container
        .read(speedBubbleSessionProvider.notifier)
        .open(SpeedBubbleMode.beatDensity);
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('clamp_paint_probe')),
    );
    late int imageWidth;
    late ByteData pixels;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      imageWidth = image.width;
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });

    final band = paintedBubbleBand(pixels, imageWidth);
    expect(band.top, greaterThanOrEqualTo(0), reason: '气泡应画出来（近黑带在场）');
    // 命中/几何口径的气泡矩形（外框 = Material 矩形，与近黑带同物）。
    final hitRect = tester.getRect(find.byKey(const Key('speed_bubble')));
    // 取带中心比较：Material 阴影使绘制带上下各宽出数像素，中心不受影响。
    expect(
      (band.top + band.bottom) / 2,
      closeTo(hitRect.center.dy, 3),
      reason: '绘制中心必须与命中中心重合（画点不一致 = 看得见的按钮点不动）',
    );
  });
}
