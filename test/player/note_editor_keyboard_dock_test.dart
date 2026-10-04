import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/note_editor_harness.dart';

/// 「键盘感知停靠」widget 缝直测：键盘升起输入条
/// 整体位移到键盘上沿之上、开合只是位移不是形态切换；停靠只在呈现层、
/// 编辑不改贴纸持久化几何；停靠位逐帧跟随键盘 inset（升起动画的中间帧
/// 不钉住）；点「完成」与点输入条以外任意处都收起并保存（净变化才提交）；
/// 输入条高于安全带时呈现层临时缩小、退出恢复。
void main() {
  late ProviderContainer container;

  setUp(() {
    container = noteEditorContainer();
    addTearDown(container.dispose);
  });

  Future<void> pumpPanel(WidgetTester tester) =>
      pumpNoteEditorPanel(tester, container);

  Rect editorRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('note_text_editor')));

  /// 设键盘下沿 inset（[logicalHeight] 逻辑像素；测试面 dpr = 3.0），测试
  /// 结束恢复窗口。
  void setKeyboardInset(WidgetTester tester, double logicalHeight) {
    addTearDown(tester.view.reset);
    tester.view.viewInsets = FakeViewPadding(bottom: logicalHeight * 3);
  }

  testWidgets('键盘升起：输入条整体位移到键盘上沿之上，文本与全部工具可见', (tester) async {
    setKeyboardInset(tester, 300);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    final rect = editorRect(tester);
    expect(
      rect.bottom,
      lessThanOrEqualTo(600 - 300),
      reason: '输入条下沿必须落在键盘上沿之上',
    );
    expect(find.byKey(const Key('note_text_editor_field')), findsOneWidget);
    // 样式入口退场，留下的工具钮全带文字。
    for (final label in ['删除', '完成']) {
      expect(find.text(label), findsOneWidget, reason: '停靠后工具仍全在：$label');
    }
    expect(find.text('描边'), findsNothing);
    expect(find.text('最近'), findsNothing);
    expect(
      find.byKey(const Key('note_editor_roster_strip')),
      findsOneWidget,
      reason: '停靠后舞者快捷区仍全在',
    );
  });

  testWidgets('键盘开合：停靠位移到键盘上沿、收起回到底部原位（词条条换入工具行）', (tester) async {
    addTearDown(tester.view.reset);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);
    final restRect = editorRect(tester);

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    final dockedRect = editorRect(tester);
    expect(dockedRect.bottom, lessThan(restRect.bottom));
    // 单行形态——键盘开合只是位移，行高不变、无布局跳动。
    expect(dockedRect.height, restRect.height);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(editorRect(tester), restRect, reason: '回到底部原位');
  });

  testWidgets('真机键盘升起动画：中间帧不能把停靠位钉在半路', (tester) async {
    addTearDown(tester.view.reset);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    // DNP-AN00（API 36，横屏）实测序列：viewInsets.bottom 逐帧到达，首个
    // 非零值只有 18.29 逻辑像素，稳定值 255.14——按首个非零值停靠会把输入
    // 条留在键盘后面。
    for (final inset in [
      18.285714285714285,
      167.71428571428572,
      201.14285714285714,
      232.0,
      255.14285714285714,
    ]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset * 3);
      await tester.pump();
    }

    expect(
      editorRect(tester).bottom,
      lessThanOrEqualTo(600 - 255.14285714285714),
      reason: '停靠位必须落在稳定后的键盘上沿之上',
    );
  });

  testWidgets('已停靠后 metrics 再变跟随：键盘变高变矮都跟着位移', (tester) async {
    addTearDown(tester.view.reset);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    tester.view.viewInsets = const FakeViewPadding(bottom: 900); // 300 逻辑
    await tester.pump();
    expect(editorRect(tester).bottom, lessThanOrEqualTo(600 - 300));

    tester.view.viewInsets = const FakeViewPadding(bottom: 1350); // 450 逻辑
    await tester.pump();
    expect(
      editorRect(tester).bottom,
      lessThanOrEqualTo(600 - 450),
      reason: '键盘变高：跟随着抬起',
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 600); // 200 逻辑
    await tester.pump();
    final settled = editorRect(tester);
    expect(settled.bottom, lessThanOrEqualTo(600 - 200), reason: '键盘变矮：跟随着落');
    expect(settled.bottom, greaterThan(600 - 450), reason: '不再是钉死的高位');
  });

  testWidgets('停靠不涉及持久化状态：编辑前后贴纸持久化位置与大小逐位相同', (tester) async {
    setKeyboardInset(tester, 300);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);
    final before = container.read(noteStickersProvider).single;

    await tester.enterText(
      find.byKey(const Key('note_text_editor_field')),
      '停靠编辑不改几何',
    );
    await tester.tap(find.byKey(const Key('note_editor_done')));
    await tester.pump();

    final after = container.read(noteStickersProvider).single;
    expect(after.text, '停靠编辑不改几何');
    expect(after.geometry.centerX, before.geometry.centerX);
    expect(after.geometry.centerY, before.geometry.centerY);
    expect(after.geometry.scale, before.geometry.scale);
    expect(after.startMs, before.startMs);
    expect(after.endMs, before.endMs);
  });

  testWidgets('编辑器内没有任何停靠文案：升起、停靠、收起全程只有输入条', (tester) async {
    addTearDown(tester.view.reset);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    expect(find.textContaining('停靠'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('停靠'), findsNothing);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(find.textContaining('停靠'), findsNothing);
  });

  testWidgets('点输入条以外任意处收起并保存（净变化才提交）', (tester) async {
    addTearDown(tester.view.reset);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    await tester.enterText(
      find.byKey(const Key('note_text_editor_field')),
      '点外收起',
    );
    await tester.tapAt(const Offset(30, 30));
    await tester.pump();
    expect(container.read(noteStickersProvider).single.text, '点外收起');
    expect(find.byKey(const Key('note_text_editor')), findsNothing);

    // 再开不改文本、点外收起：不发起命令（撤销栈深度不变）。
    container.read(noteTextEditorTargetProvider.notifier).open(10000);
    await pumpPanel(tester);
    final canUndoBefore = container.read(annotationEditHistoryProvider).canUndo;
    await tester.tapAt(const Offset(30, 30));
    await tester.pump();
    expect(
      container.read(annotationEditHistoryProvider).canUndo,
      canUndoBefore,
    );
    expect(find.byKey(const Key('note_text_editor')), findsNothing);
  });

  testWidgets('输入条高于安全带时呈现层临时缩小；键盘收起恢复原大', (tester) async {
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    setKeyboardInset(tester, 560);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);
    await tester.pumpAndSettle();
    final shrunkRect = editorRect(tester);
    expect(
      shrunkRect.bottom,
      lessThanOrEqualTo(600 - 560),
      reason: '缩小后仍要完整落在键盘上沿之上',
    );

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    final restored = editorRect(tester);
    expect(
      restored.height,
      greaterThan(shrunkRect.height),
      reason: '退出编辑（键盘收起）恢复原尺寸',
    );
  });
}
