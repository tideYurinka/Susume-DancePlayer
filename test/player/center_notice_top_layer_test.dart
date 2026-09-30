import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/control_layer.dart';
import 'package:dance_learning_app/player/notice.dart'
    show
        NoticeId,
        noticeTriggerProvider;
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/stack_paint_order.dart';
import '../helpers/beat_test_seam.dart' show hangingBeatPipeline;

/// 屏幕中央短暂提示提层：宿主在页面 Stack 里绘制于
/// 控制层与备注文本编辑器面之后的栈序断言收在宿主接缝一处
/// （`notice_host_test.dart`）；此处逐身份验「触发 → 可见」（九条中央
/// 提示），另钉装载门定位 key、三指提示栈序与点按穿透。语义不变——纯
/// 视觉（点按穿透）、定时自动消退、无模型变更。
void main() {
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
  }) async {
    final resolved = Uri.file('/videos/a.mp4');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(
            hangingBeatPipeline,
          ),
          // 固定摘要 + 内存文档存储：装载门即刻落定，编辑器入口不被挡。
          contentHasherProvider.overrideWithValue(const FixedHasher('vid-a')),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => InMemoryVideoDocumentStorage(),
          ),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
        ],
        child: MaterialApp(home: PlayerPage(source: resolved)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 单击画面展开控制层（编辑态）。
  Future<void> openControlLayer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  /// 三指右滑跳转（提示于跳转瞬间出现）。
  Future<void> threeFingerSwipeRight(WidgetTester tester) async {
    final g1 = await tester.startGesture(const Offset(320, 300));
    final g2 = await tester.startGesture(const Offset(360, 300));
    final g3 = await tester.startGesture(const Offset(400, 300));
    await tester.pump();
    for (final g in [g1, g2, g3]) {
      await g.moveBy(const Offset(60, 0));
    }
    await tester.pump();
    for (final g in [g1, g2, g3]) {
      await g.up();
    }
    await tester.pump();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

  /// 断言 [noticeFinder]（须已在树上）在页面共享 Stack 的绘制序位于
  /// 控制层与备注文本编辑器面之后（宿主的栈序断言收在此一处）。
  void expectAboveControlLayerAndNoteEditor(
    WidgetTester tester,
    Finder noticeFinder,
    String label,
  ) {
    final stack = sharedStackOf(
      tester,
      find.byType(ControlLayer),
      noticeFinder,
    );
    final noticeIndex = paintIndexOf(stack, tester.element(noticeFinder));
    final controlIndex = paintIndexOf(
      stack,
      tester.element(find.byType(ControlLayer)),
    );
    final editorIndex = paintIndexOf(
      stack,
      tester.element(find.byType(NoteTextEditorPanel)),
    );
    expect(noticeIndex, greaterThan(controlIndex), reason: '$label 应绘制在控制层之后');
    expect(
      noticeIndex,
      greaterThan(editorIndex),
      reason: '$label 应绘制在备注文本编辑器面之后',
    );
  }

  /// 九个中央提示的触发方式与可见文案。
  final cases = <String, void Function(WidgetTester tester)>{
    '已锁定分段': (tester) =>
        containerOf(tester).read(noticeTriggerProvider(NoticeId.layoutLock).notifier).show(),
    '备注已锁定': (tester) =>
        containerOf(tester).read(noticeTriggerProvider(NoticeId.noteContentLock).notifier).show(),
    '节拍分析中…': (tester) => containerOf(tester)
        .read(noticeTriggerProvider(NoticeId.beatAnalyzing).notifier)
        .show(),
    '无节拍数据': (tester) => containerOf(tester)
        .read(noticeTriggerProvider(NoticeId.beatNoData).notifier)
        .show(),
    '节拍提示已关闭 · 编辑态顶栏可重新打开': (tester) => containerOf(tester)
        .read(noticeTriggerProvider(NoticeId.beatOverlayClose).notifier)
        .show(),
    '已启用步进倍速': (tester) => containerOf(tester)
        .read(noticeTriggerProvider(NoticeId.stepEnabled).notifier)
        .show(),
    // 局部镜像无片段已走新路：触发面只报身份。
    '请添加局部镜像片段': (tester) => containerOf(tester)
        .read(noticeTriggerProvider(NoticeId.localMirrorEmpty).notifier)
        .show(),
    '太靠近结尾，无法起录': (tester) => containerOf(tester)
        .read(noticeTriggerProvider(NoticeId.compareRecordRejected).notifier)
        .show(),
    '正在装载': (tester) => containerOf(tester)
        .read(noticeTriggerProvider(NoticeId.loadGate).notifier)
        .show(),
  };

  void runCase(
    String label,
    void Function(WidgetTester tester) trigger,
  ) {
    testWidgets('「$label」触发后可见（宿主唯一渲染）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await openControlLayer(tester);
      expect(find.byType(ControlLayer), findsOneWidget);

      trigger(tester);
      await tester.pump();

      expect(find.text(label), findsOneWidget, reason: '$label 提示应可见');
    });
  }

  for (final entry in cases.entries) {
    runCase(entry.key, entry.value);
  }

  testWidgets('宿主绘制于控制层与备注文本编辑器面之后（栈序收在宿主一处）',
      (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
    await pumpPlayer(tester, engine: engine);
    await openControlLayer(tester);
    expect(find.byType(ControlLayer), findsOneWidget);

    containerOf(tester)
        .read(noticeTriggerProvider(NoticeId.layoutLock).notifier)
        .show();
    await tester.pump();

    final noticeFinder = find.text('已锁定分段');
    expect(noticeFinder, findsOneWidget);
    expectAboveControlLayerAndNoteEditor(tester, noticeFinder, '宿主');
  });

  testWidgets('「正在装载」提示由定位 key load_gate_prompt 定位（key 钉住）',
      (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
    await pumpPlayer(tester, engine: engine);
    await openControlLayer(tester);

    containerOf(tester)
        .read(noticeTriggerProvider(NoticeId.loadGate).notifier)
        .show();
    await tester.pump();

    expect(find.text('正在装载'), findsOneWidget);
    expect(find.byKey(const Key('load_gate_prompt')), findsOneWidget);
  });

  testWidgets('三指「已跳转」提示手势触发后可见（宿主唯一渲染）', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
    await pumpPlayer(tester, engine: engine);

    // 三指手势落在播放手势层：先滑动（控制层收起时），提示停留窗口内
    // 单击展开控制层后再断言可见。
    await threeFingerSwipeRight(tester);
    await openControlLayer(tester);
    expect(find.byType(ControlLayer), findsOneWidget);
    await tester.pump();
    expect(find.text('已跳转'), findsOneWidget);
  });

  testWidgets('提示显示期间不拦触摸：单击照常穿透并收起控制层', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
    await pumpPlayer(tester, engine: engine);
    await openControlLayer(tester);
    expect(find.byType(ControlLayer), findsOneWidget);

    containerOf(tester).read(noticeTriggerProvider(NoticeId.layoutLock).notifier).show();
    await tester.pump();
    expect(find.text('已锁定分段'), findsOneWidget);

    // 提示不进 gesture arena：单击点在提示自身位置，穿透到提示下方的
    // 控制层面（warnIfMissed:false——落点由提示 finder 给出，预期命中的
    // 是其下方的控制层面而非提示本身），收起控制层。
    await tester.tap(find.text('已锁定分段'), warnIfMissed: false);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
    expect(find.byType(ControlLayer), findsNothing);
  });
}
