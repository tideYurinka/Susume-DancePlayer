import 'package:dance_learning_app/player/notice.dart';
import 'package:dance_learning_app/core/notice_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stack_paint_order.dart';

/// 提示宿主接缝：挂一条宿主 → 触发某身份
/// → 屏幕正中恰好一条胶囊、key 与内容对、绘制在既挂的控制层替身之后 →
/// 推进该身份的停留 → 消失；再触发另一身份 → 前一条被接管（同屏只有一条）。
void main() {
  const localMirrorSpec = NoticeSpec(
    id: NoticeId.localMirrorEmpty,
    content: _textA,
    noticeKey: Key('host_notice_a'),
  );
  const overlayCloseSpec = NoticeSpec(
    id: NoticeId.beatOverlayClose,
    content: _textB,
    noticeKey: Key('host_notice_b'),
  );

  Widget host(WidgetTester tester, List<NoticeSpec> specs) {
    return ProviderScope(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            // 控制层替身：宿主须绘制在它之后（顶层语义）。
            const SizedBox.expand(key: Key('stand_in_control_layer')),
            NoticeHost(specs: specs),
          ],
        ),
      ),
    );
  }

  void trigger(WidgetTester tester, NoticeId id) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NoticeHost)),
      listen: false,
    );
    container.read(noticeTriggerProvider(id).notifier).show();
  }

  testWidgets('触发身份 → 屏幕正中恰好一条胶囊，key 与内容对，绘制在控制层替身之后', (
    tester,
  ) async {
    await tester.pumpWidget(host(tester, const [localMirrorSpec]));
    expect(find.byType(NoticeBadge), findsNothing);

    trigger(tester, NoticeId.localMirrorEmpty);
    await tester.pump();

    expect(find.byType(NoticeBadge), findsOneWidget);
    expect(find.byKey(const Key('host_notice_a')), findsOneWidget);
    expect(find.text('内容甲'), findsOneWidget);
    // 全站黑底胶囊默认档的渲染尺寸（卡体收窄只走两张提示卡自己的口子；
    // 「内容甲」+ 默认内边距 16 × 10）。
    final hostBadge = tester.getSize(find.byKey(const Key('host_notice_a')));
    expect(hostBadge.width, closeTo(74.8, 0.05));
    expect(hostBadge.height, closeTo(40, 0.05));

    final stack = sharedStackOf(
      tester,
      find.byKey(const Key('stand_in_control_layer')),
      find.byKey(const Key('host_notice_a')),
    );
    final noticeIndex = paintIndexOf(
      stack,
      tester.element(find.byKey(const Key('host_notice_a'))),
    );
    final standInIndex = paintIndexOf(
      stack,
      tester.element(find.byKey(const Key('stand_in_control_layer'))),
    );
    expect(noticeIndex, greaterThan(standInIndex), reason: '宿主绘制在最顶层');
  });

  testWidgets('推进该身份的停留 → 消失（时长取该身份的表值）', (tester) async {
    await tester.pumpWidget(host(tester, const [localMirrorSpec]));
    trigger(tester, NoticeId.localMirrorEmpty);
    await tester.pump();
    expect(find.byType(NoticeBadge), findsOneWidget);

    await tester.pump(noticeTimingOf(NoticeId.localMirrorEmpty).hold);
    expect(find.byType(NoticeBadge), findsNothing);
  });

  testWidgets('后触发者接管：同屏只有一条，前一条消失', (tester) async {
    await tester.pumpWidget(host(tester, const [localMirrorSpec, overlayCloseSpec]));
    trigger(tester, NoticeId.localMirrorEmpty);
    await tester.pump();
    expect(find.byKey(const Key('host_notice_a')), findsOneWidget);

    trigger(tester, NoticeId.beatOverlayClose);
    await tester.pump();

    expect(find.byType(NoticeBadge), findsOneWidget, reason: '同屏只有一条');
    expect(find.byKey(const Key('host_notice_a')), findsNothing);
    expect(find.byKey(const Key('host_notice_b')), findsOneWidget);
    expect(find.text('内容乙'), findsOneWidget);
  });

  testWidgets('同一身份连续触发两次：停留定时重排，不提前消失', (tester) async {
    await tester.pumpWidget(host(tester, const [localMirrorSpec]));
    final hold = noticeTimingOf(NoticeId.localMirrorEmpty).hold;

    trigger(tester, NoticeId.localMirrorEmpty);
    await tester.pump();

    await tester.pump(hold - const Duration(milliseconds: 10));
    trigger(tester, NoticeId.localMirrorEmpty);
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byType(NoticeBadge), findsOneWidget, reason: '重排后仍在停留');
    expect(find.text('内容甲'), findsOneWidget, reason: '同一身份不换内容');

    await tester.pump(noticeTimingOf(NoticeId.localMirrorEmpty).hold);
    expect(find.byType(NoticeBadge), findsNothing);
  });

  testWidgets('换身份时销毁旧控制器：旧身份的停留定时不再点燃', (tester) async {
    await tester.pumpWidget(host(tester, const [localMirrorSpec, overlayCloseSpec]));
    trigger(tester, NoticeId.localMirrorEmpty);
    await tester.pump();
    expect(find.byKey(const Key('host_notice_a')), findsOneWidget);

    // 立刻换身份：旧控制器销毁，其 hold（1500ms）到点不得把宿主拉回可见；
    // 新身份停留 2000ms，此刻仍在。
    trigger(tester, NoticeId.beatOverlayClose);
    await tester.pump(noticeTimingOf(NoticeId.localMirrorEmpty).hold +
        const Duration(milliseconds: 100));
    expect(find.byKey(const Key('host_notice_a')), findsNothing);
    expect(find.byKey(const Key('host_notice_b')), findsOneWidget,
        reason: '新身份按自己的时长继续停留');
  });
}

Widget _textA(BuildContext _) => const Text('内容甲', style: TextStyle());
Widget _textB(BuildContext _) => const Text('内容乙', style: TextStyle());
