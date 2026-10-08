import 'package:dance_learning_app/player/notice.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// 提示模块声明数据断言：
///
/// - 每个身份有且只有一个声明被组合根装配；每个身份的时长查询返回
///   非零停留；
/// - 身份枚举十三个取值一次声明齐；未列出的身份取缺省。
void main() {
  group('声明覆盖与时长非零', () {
    test('每个身份有且只有一个声明被组合根装配', () {
      for (final id in NoticeId.values) {
        final count = kNoticeSpecs.where((spec) => spec.id == id).length;
        expect(count, 1, reason: '$id 应恰好装配一条声明');
      }
    });

    test('每个身份的时长查询返回非零停留', () {
      for (final id in NoticeId.values) {
        expect(
          noticeTimingOf(id).hold,
          greaterThan(Duration.zero),
          reason: '$id 停留时长必须非零',
        );
      }
    });
  });

  group('声明数据（身份枚举与时长表）', () {
    test('身份枚举十五个取值一次声明齐（增「无对象」；增「文档只读」；增投屏两条）', () {
      expect(NoticeId.values, hasLength(15));
      expect(
        NoticeId.values.toSet(),
        equals({
          NoticeId.stepEnabled,
          NoticeId.beatOverlayClose,
          NoticeId.beatAnalyzing,
          NoticeId.beatNoData,
          NoticeId.loadGate,
          NoticeId.localMirrorEmpty,
          NoticeId.layoutLock,
          NoticeId.noSubject,
          NoticeId.noteContentLock,
          NoticeId.compareRecordRejected,
          NoticeId.threeFingerToast,
          NoticeId.transition,
          NoticeId.documentReadOnly,
          NoticeId.castInterrupted,
          NoticeId.castNotStarted,
        }),
      );
    });

    test('未列出的身份取缺省（缺省 + 只列例外）', () {
      // 表是决定而非不变量：只断言缺省回落行为，不断言例外条目数值快照
      // （不新增「时长表快照」断言）。
      expect(
        noticeTimingOf(NoticeId.localMirrorEmpty).hold,
        kDefaultNoticeHold,
      );
      expect(noticeTimingOf(NoticeId.localMirrorEmpty).fade, Duration.zero);
      expect(
        noticeTimingOf(NoticeId.transition).fade,
        isNot(Duration.zero),
        reason: '例外条目确有落表',
      );
    });
  });
}
