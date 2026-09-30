import 'package:dance_learning_app/core/frame_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// scrub 指示浮层时间文本格式（现为共享 [formatFrameTime]，
/// mm:ss:ff 帧号自 0——纯函数本体在 `frame_time_test.dart` 详测，此处保留
/// 格式接入回归：浮层文本格式与控制层时间读数同源、无私有格式分叉）。
///
/// widget 级行为（出现/更新/消失、IgnorePointer、时长未知分支）在
/// `player_page_test.dart` 的「scrub 指示浮层」组中经
/// FakeEngine + 手势拖动断言。
void main() {
  group('浮层时间文本格式接入（mm:ss:ff，经共享 formatFrameTime）', () {
    test('0 → 00:00:00（取代旧 mm:ss.d 十分位格式）', () {
      expect(formatFrameTime(Duration.zero), '00:00:00');
    });

    test('帧号自 0 起、默认 30fps 换算正确', () {
      expect(formatFrameTime(const Duration(milliseconds: 500)), '00:00:15');
      expect(formatFrameTime(const Duration(seconds: 1)), '00:01:00');
    });
  });
}
