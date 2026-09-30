import 'package:dance_learning_app/core/playback/display_aspect_ratio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 显示比例换算纯件直测（判据与理由见 `display_aspect_ratio.dart` 库头）。
///
/// 期望值取实数，不复写实现公式。
void main() {
  group('旋转量 0 / 180 / 缺失：不交换', () {
    test('0：横向编码保持 16:9', () {
      expect(
        displayAspectRatio(width: 1920, height: 1080, rotation: 0),
        closeTo(16 / 9, 1e-9),
      );
    });

    test('0：竖向编码保持 9:16', () {
      expect(
        displayAspectRatio(width: 1080, height: 1920, rotation: 0),
        closeTo(9 / 16, 1e-9),
      );
    });

    test('180：与 0 同解', () {
      expect(
        displayAspectRatio(width: 1920, height: 1080, rotation: 180),
        closeTo(16 / 9, 1e-9),
      );
    });

    test('缺失：按 0 处理', () {
      expect(
        displayAspectRatio(width: 1920, height: 1080),
        closeTo(16 / 9, 1e-9),
      );
    });
  });

  group('旋转量 90 / 270 / 负值：交换', () {
    test('90：横向编码 + 旋转 → 显示朝向变竖（本机素材 3840×2160 + 旋转）', () {
      expect(
        displayAspectRatio(width: 3840, height: 2160, rotation: 90),
        closeTo(2160 / 3840, 1e-9),
      );
    });

    test('270：与 90 同解', () {
      expect(
        displayAspectRatio(width: 3840, height: 2160, rotation: 270),
        closeTo(2160 / 3840, 1e-9),
      );
    });

    test('-90：与 90 同解', () {
      expect(
        displayAspectRatio(width: 3840, height: 2160, rotation: -90),
        closeTo(2160 / 3840, 1e-9),
      );
    });

    test('360：判据只看「是不是 0 或 180」，不做取模归一化', () {
      expect(
        displayAspectRatio(width: 1920, height: 1080, rotation: 360),
        closeTo(1080 / 1920, 1e-9),
      );
    });
  });

  group('未知与退化输入一律 null', () {
    test('宽高任一缺失', () {
      expect(displayAspectRatio(height: 1080, rotation: 0), isNull);
      expect(displayAspectRatio(width: 1920, rotation: 0), isNull);
      expect(displayAspectRatio(rotation: 90), isNull);
    });

    test('宽高任一非正', () {
      expect(displayAspectRatio(width: 1920, height: 0), isNull);
      expect(displayAspectRatio(width: 0, height: 1080), isNull);
      expect(displayAspectRatio(width: 1920, height: -1080), isNull);
      expect(
        displayAspectRatio(width: 0, height: 1080, rotation: 90),
        isNull,
        reason: '交换后宽度 0',
      );
      expect(
        displayAspectRatio(width: 1920, height: 0, rotation: 90),
        isNull,
        reason: '交换后高度 0',
      );
    });
  });
}
