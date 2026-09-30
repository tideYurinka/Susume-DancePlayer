import 'package:dance_learning_app/player/no_subject_hint.dart';
import 'package:dance_learning_app/player/tool_slots.dart' show NoSubjectHint;
import 'package:flutter_test/flutter_test.dart';

/// （灰钮给做法）：无对象提示文案的直测——两态取辞与按入口分派。
/// 纯 Dart、不启动 widget 环境。
void main() {
  group('无对象做法文案', () {
    test('已有分段 → 指出要先选中作用对象，按入口取辞', () {
      expect(
        noSubjectHintText(NoSubjectHint.learningSegment,
            hasSegments: true),
        '先点一段再点这里',
      );
      expect(
        noSubjectHintText(NoSubjectHint.segmentLine, hasSegments: true),
        '先选中一条分段线，再点这里标记',
      );
      expect(
        noSubjectHintText(NoSubjectHint.segmentLineOrClip,
            hasSegments: true),
        '先选中一条分段线或片段，再点这里删除',
      );
    });

    test('一条分段都没有 → 指出更前面的一步（先切出段来），与入口无关', () {
      for (final selection in NoSubjectHint.values) {
        expect(
          noSubjectHintText(selection, hasSegments: false),
          '先用『分段』或『自动分段』切出段来',
          reason: '$selection',
        );
      }
      expect(kNoSubjectNoSegmentsText, '先用『分段』或『自动分段』切出段来');
    });
  });
}
