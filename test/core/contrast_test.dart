import 'package:dance_learning_app/core/contrast.dart';
import 'package:dance_learning_app/core/system_page_text_colors.dart';
import 'package:flutter_test/flutter_test.dart';

/// 对比度下限判定（纯函数接缝）：4.5:1 的判定是纯函数（相对亮度 → 对比度），
/// 断言落在视觉 token 取值上——期望值取自下限与各处实际压着的底色，不从实现
/// 推导。控制层 token 与系统页 token 共用这一份判定函数。
///
/// 亮度与对比度锚点取自 WCAG 2.x 定义：白/黑对比 21:1、下限 4.5:1 处
/// （`#767676` 对白 = 4.54）取紧贴下限之上的取值作正例。
void main() {
  const white = 0xFFFFFFFF;
  const black = 0xFF000000;

  group('纯函数锚点（WCAG 定义）', () {
    test('纯白相对亮度为 1，纯黑为 0', () {
      expect(relativeLuminance(white), closeTo(1, 1e-9));
      expect(relativeLuminance(black), closeTo(0, 1e-9));
    });

    test('白对黑对比 21:1，与顺序无关', () {
      expect(contrastRatio(white, black), closeTo(21, 0.01));
      expect(contrastRatio(black, white), contrastRatio(white, black));
    });

    test('中灰 #767676 对白在 4.5:1 之上、#777777 在之下（下限的两侧）', () {
      expect(contrastRatio(0xFF767676, white), greaterThan(4.5));
      expect(contrastRatio(0xFF777777, white), lessThan(4.5));
    });

    test('达标判定吃实际底色：同前景不同底结论可不同', () {
      // 判定只对不透明取值负责：半透明前景先由调用方合成到底色再传入
      // （按文字实际压着的底色算）。同一灰档压白不达
      // 标、压黑达标——底色换结论就换。
      const gray = 0xFF777777;
      expect(meetsContrastFloor(gray, white), isFalse);
      expect(meetsContrastFloor(gray, black), isTrue);
      expect(meetsContrastFloor(0xFF767676, white), isTrue);
    });
  });

  group('系统页文字 token（分享面板警告 / 备份对话框说明）', () {
    test('分享面板警告橙对白色系底达到 4.5:1（色相家族不变）', () {
      // 实际底色是分享面对话框的浅色 surface（近白）：对纯白与 M3 淡紫
      // seed 的 surface 两处都判，取值的深橙档压在浅色系底上都要达标。
      expect(contrastRatio(kShareWarningTextColor.toARGB32(), white), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(kShareWarningTextColor.toARGB32(), 0xFFFEF7FF), greaterThanOrEqualTo(4.5));
    });

    test('备份对话框说明绿对白色系底达到 4.5:1（色相家族不变）', () {
      expect(contrastRatio(kBackupNoteTextColor.toARGB32(), white), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(kBackupNoteTextColor.toARGB32(), 0xFFFEF7FF), greaterThanOrEqualTo(4.5));
    });

    test('两处 token 走同一份达标判定', () {
      expect(meetsContrastFloor(kShareWarningTextColor.toARGB32(), white), isTrue);
      expect(meetsContrastFloor(kBackupNoteTextColor.toARGB32(), white), isTrue);
    });
  });
}
