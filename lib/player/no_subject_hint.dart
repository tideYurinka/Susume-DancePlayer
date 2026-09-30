/// 「无对象」门的做法提示。
///
/// 没有作用对象时，**熟练度 / 重点 / 删除 /「添加」菜单里的「标记分段线」**
/// 四个入口置灰但**按得动**：按一下弹一句「该怎么做」，动作照样不发生。
/// 提示走既有的**短暂提示**胶囊浮层（与「已锁定分段」「节拍分析中…」同一条
/// 路径），每次按都弹。「哪一句」由入口在判定表里声明
/// （`tool_slots.dart` 的 [NoSubjectHint]），本库只把声明翻成文案。
///
/// 文案按**这支舞有没有分段**两态取辞：
/// - 已有分段 —— 指出要先选中作用对象（按入口说是哪一种）；
/// - 一条分段都没有 —— 指出更前面的一步（先切出段来）。「没有作用对象」
///   最常见的原因恰恰是还没切过分段，这时让人「先选中」是句空话。
///
/// 「这支舞有没有分段」是**事实**（派生学习段是否为空），按与三指跳转方向
/// 注入点同款的写法与入口声明一起经 [noSubjectFactsProvider] 注入；内容
/// 声明因此仍是常量（由事实取值），渲染归演出层唯一宿主。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notice.dart' show NoticeId, NoticeSpec, noticeTriggerProvider;
import 'tool_slots.dart' show NoSubjectHint;
import 'visual_tokens.dart' show kNoticeTextStyle;

/// 「这支舞一条分段都没有」态的做法文案（唯一一份生产取值；测试逐字
/// 重写期望值，故意不从本常量取——文案改了要能在测试里看见）。
const String kNoSubjectNoSegmentsText = '先用『分段』或『自动分段』切出段来';

/// 「无对象」做法文案：按入口声明的 [hint] 与「这支舞有没有分段」两态取辞。
String noSubjectHintText(
  NoSubjectHint hint, {
  required bool hasSegments,
}) {
  if (!hasSegments) return kNoSubjectNoSegmentsText;
  return switch (hint) {
    NoSubjectHint.learningSegment => '先点一段再点这里',
    NoSubjectHint.segmentLine => '先选中一条分段线，再点这里标记',
    NoSubjectHint.segmentLineOrClip => '先选中一条分段线或片段，再点这里删除',
  };
}

/// 一次「无对象」提示的两项**事实**：入口声明的做法 + 这支舞此刻有没有
/// 分段。内容由事实取值（[noSubjectHintText]），注入点里不放渲染好的文字。
typedef NoSubjectFacts = ({NoSubjectHint hint, bool hasSegments});

/// 无对象提示当前那两项事实（由按下那一处写入；重复按即重排停留）。
///
/// 缺省值不参与演出（触发前必先写入），取一组有定义的事实只为让状态永远
/// 非空——与三指跳转方向的缺省同款。
class NoSubjectFactsModel extends Notifier<NoSubjectFacts> {
  @override
  NoSubjectFacts build() =>
      (hint: NoSubjectHint.learningSegment, hasSegments: true);

  /// 写入这一次的两项事实。
  void write(NoSubjectFacts facts) => state = facts;
}

/// 无对象提示事实注入点。
final noSubjectFactsProvider =
    NotifierProvider<NoSubjectFactsModel, NoSubjectFacts>(
  NoSubjectFactsModel.new,
);

/// 「无对象」提示内容（按注入的事实取那一句）。
Widget noSubjectNoticeContent(BuildContext _) =>
    const _NoSubjectNoticeContent();

class _NoSubjectNoticeContent extends ConsumerWidget {
  const _NoSubjectNoticeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = ref.watch(noSubjectFactsProvider);
    return Text(
      noSubjectHintText(facts.hint, hasSegments: facts.hasSegments),
      style: kNoticeTextStyle,
    );
  }
}

/// 「无对象」提示声明（组合根装配，每次按都弹）。
const noSubjectNoticeSpec = NoticeSpec(
  id: NoticeId.noSubject,
  content: noSubjectNoticeContent,
  noticeKey: Key('no_subject_prompt'),
);

/// 触发「无对象」做法提示：写入这一次的事实 → 报身份；动作不发生。
void showNoSubjectHint(
  WidgetRef ref,
  NoSubjectHint hint, {
  required bool hasSegments,
}) {
  ref
      .read(noSubjectFactsProvider.notifier)
      .write((hint: hint, hasSegments: hasSegments));
  ref.read(noticeTriggerProvider(NoticeId.noSubject).notifier).show();
}
