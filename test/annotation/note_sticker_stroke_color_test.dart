import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:flutter_test/flutter_test.dart';

/// 描边取色判据直测（外层黑边支）：描边恒开、
/// 颜色由该段底色派生——感知亮度 `(0.299R + 0.587G + 0.114B) / 255 > 0.40`
/// 描黑边、否则描白边；**纯白点名固定描白边**（不走判据）；**正文段固定
/// 黑边**（不走判据）。判据按段、不按字。纯白点名段的**外层黑边**取色
/// 由 [noteSegmentOuterStrokeColor] 单独给出——仅纯白点名返回黑，其余一律
/// null（不挂外层）。
void main() {
  double luminanceOf(int argb) =>
      (0.299 * ((argb >> 16) & 0xFF) +
          0.587 * ((argb >> 8) & 0xFF) +
          0.114 * (argb & 0xFF)) /
      255;

  group('备注段描边取色', () {
    test('正文段固定黑边（不走亮度判据）', () {
      // 深色与浅色正文都描黑边——正文恒为白字，与底色无关。
      expect(
        noteSegmentStrokeColor(0xFF000000, mention: false),
        kNoteStrokeBlackColor,
      );
      expect(
        noteSegmentStrokeColor(0xFFFFFFFF, mention: false),
        kNoteStrokeBlackColor,
      );
      expect(
        noteSegmentStrokeColor(0xFFFDD835, mention: false),
        kNoteStrokeBlackColor,
      );
    });

    test('纯白点名固定描白边（不走亮度判据）', () {
      expect(
        noteSegmentStrokeColor(0xFFFFFFFF, mention: true),
        kNoteStrokeWhiteColor,
      );
    });

    test('阈值 0.40 两侧：浅色点名描黑边', () {
      // 黄（亮度 ≈ 0.84 > 0.40）→ 黑边。
      const yellow = 0xFFFDD835;
      expect(luminanceOf(yellow), greaterThan(0.40));
      expect(
        noteSegmentStrokeColor(yellow, mention: true),
        kNoteStrokeBlackColor,
      );
      // 近阈值浅侧：中灰偏亮（亮度 ≈ 0.5 > 0.40）→ 黑边。
      const lightGray = 0xFF808080;
      expect(luminanceOf(lightGray), greaterThan(0.40));
      expect(
        noteSegmentStrokeColor(lightGray, mention: true),
        kNoteStrokeBlackColor,
      );
    });

    test('阈值恰等 0.40：不走黑支（判据为严格大于）', () {
      // 中灰 0x66 = 102，亮度 = 102/255 = 0.40 恰等——不大于阈值 → 白边。
      const gray = 0xFF666666;
      expect(luminanceOf(gray), moreOrLessEquals(0.40));
      expect(
        noteSegmentStrokeColor(gray, mention: true),
        kNoteStrokeWhiteColor,
      );
    });

    test('阈值 0.40 两侧：深色点名描白边', () {
      // 24 色板红（亮度 ≈ 0.423 > 0.40，判据的浅侧）→ 黑边。
      const red = 0xFFE53935;
      expect(luminanceOf(red), greaterThan(0.40));
      expect(noteSegmentStrokeColor(red, mention: true), kNoteStrokeBlackColor);
      // 近阈值深侧：中灰偏暗（亮度 ≈ 0.4 以下）→ 白边。0x64 = 100，
      // 亮度 = 100/255 ≈ 0.392 ≤ 0.40。
      const darkGray = 0xFF646464;
      expect(luminanceOf(darkGray), lessThanOrEqualTo(0.40));
      expect(
        noteSegmentStrokeColor(darkGray, mention: true),
        kNoteStrokeWhiteColor,
      );
    });

    test('正文恒白：备注正文填充色为具名常量纯白', () {
      expect(kNoteBodyColor, 0xFFFFFFFF);
    });
  });

  group('纯白点名段外层黑边取色', () {
    test('纯白点名 → 黑', () {
      expect(
        noteSegmentOuterStrokeColor(0xFFFFFFFF, mention: true),
        kNoteStrokeBlackColor,
      );
    });

    test('正文段（底色即便也是纯白）→ null', () {
      expect(noteSegmentOuterStrokeColor(0xFFFFFFFF, mention: false), isNull);
      expect(noteSegmentOuterStrokeColor(0xFF000000, mention: false), isNull);
    });

    test('红 / 黄 / 深色点名 → null', () {
      expect(noteSegmentOuterStrokeColor(0xFFE53935, mention: true), isNull);
      expect(noteSegmentOuterStrokeColor(0xFFFDD835, mention: true), isNull);
      expect(noteSegmentOuterStrokeColor(0xFF646464, mention: true), isNull);
    });

    test('近白但非纯白 → null', () {
      expect(noteSegmentOuterStrokeColor(0xFFFEFEFE, mention: true), isNull);
    });
  });
}
