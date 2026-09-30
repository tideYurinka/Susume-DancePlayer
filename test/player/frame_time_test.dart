import 'package:dance_learning_app/core/frame_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// 共享帧时间格式化与帧时长常量的纯函数单测。
///
/// widget 级接线（控制层时间读数、微调/scrub 浮层显示 mm:ss:ff、帧率源
/// 默认 30 / 可替换 demux-fps）在 `control_layer_test.dart` /
/// `scrub_indicator_test.dart` / `player_page_test.dart` 断言。
void main() {
  group('formatFrameTime（mm:ss:ff，帧号自 0，默认 30fps）', () {
    test('0 → 00:00:00（帧号自 0 起）', () {
      expect(formatFrameTime(Duration.zero), '00:00:00');
    });

    test('默认 30fps：帧号 = 秒内毫秒 × 30 / 1000 向下取整', () {
      // 1/30s ≈ 33.33ms → 第 0 帧。
      expect(formatFrameTime(const Duration(milliseconds: 33)), '00:00:00');
      // 34ms ≥ 1 帧 → 帧号 1。
      expect(formatFrameTime(const Duration(milliseconds: 34)), '00:00:01');
      // 500ms → 第 15 帧。
      expect(formatFrameTime(const Duration(milliseconds: 500)), '00:00:15');
      // 999ms 仍落在第 29 帧（不足整秒不进位）。
      expect(formatFrameTime(const Duration(milliseconds: 999)), '00:00:29');
      // 整秒 → 下一秒第 0 帧。
      expect(formatFrameTime(const Duration(seconds: 1)), '00:01:00');
    });

    test('分秒帧补足两位（1:23.5s@30fps → 01:23:15）', () {
      expect(
        formatFrameTime(
          const Duration(seconds: 83, milliseconds: 500),
        ),
        '01:23:15',
      );
    });

    test('分钟 >= 10 自然超出两位不封顶', () {
      expect(
        formatFrameTime(
          const Duration(minutes: 65, seconds: 5, milliseconds: 300),
        ),
        '65:05:09',
      );
    });

    test('可替换帧率（demux-fps）：25fps 时帧号按 25 换算', () {
      // 500ms @25fps → 第 12 帧（30fps 下为 15）。
      expect(
        formatFrameTime(const Duration(milliseconds: 500), fps: 25),
        '00:00:12',
      );
      // 40ms @25fps = 整一帧 → 帧号 1。
      expect(
        formatFrameTime(const Duration(milliseconds: 40), fps: 25),
        '00:00:01',
      );
    });
  });

  group('帧时长常量与换算（帧步进复用）', () {
    test('kDefaultVideoFps = 30', () {
      expect(kDefaultVideoFps, 30);
    });

    test('kDefaultFrameDuration = 1/30s（微秒级精度，向下取整）', () {
      expect(kDefaultFrameDuration, const Duration(microseconds: 33333));
    });

    test('frameDurationFor(fps) 按给定帧率换算', () {
      expect(frameDurationFor(25), const Duration(milliseconds: 40));
      expect(frameDurationFor(kDefaultVideoFps), kDefaultFrameDuration);
    });
  });
}
