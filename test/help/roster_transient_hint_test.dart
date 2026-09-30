import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart'
    show badgeRosterUnitId, helpGuideSteps;
import 'package:dance_learning_app/help/guide_host.dart';
import 'package:dance_learning_app/help/guide_state.dart'
    show guideResetProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationSaveSinkProvider;
import 'package:dance_learning_app/player/dancer_roster_controller.dart';
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/note_editor_harness.dart';
import '../helpers/guide_copy_fixture.dart';

/// 名册短暂提示在引导宿主接缝上的行为：第一次
/// 打开备注编辑器、键盘升起后在「名册」钮**左侧、与它同高**浮一句**浅底深字**
/// 的小浮层，最多两行、不出屏——不压暗、不吞点击、约 4 秒自散、显示过即置位
/// （第二次写备注不再出现，重置后回到触发点再演）。
void main() {
  // 文案的单一来源是随包文件。
  final message = guideStepMessage(
    helpGuideSteps.firstWhere((step) => step.unitId == badgeRosterUnitId).id,
  );
  const hintKey = Key('guide_transient_hint');
  const rosterKey = Key('note_editor_roster');

  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    required InMemoryPrivateJsonStorage storage,
    required Size view,
    double keyboardInset = 0,
    int dancers = 0,
  }) async {
    // 合成档视口（入参 view；dpr 1.0），非设备档。
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
        playbackEngineProvider.overrideWithValue(
          FakePlaybackEngine(duration: const Duration(minutes: 1)),
        ),
        annotationSaveSinkProvider.overrideWithValue(NopSaveSink()),
      ],
    );
    addTearDown(container.dispose);
    final roster = container.read(dancerRosterControllerProvider);
    for (var i = 0; i < dancers; i++) {
      await roster.addDancer('舞者$i', color: 0xFF000000 + i);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: GuideHost(
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: NoteTextEditorPanel(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  Rect rectOf(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

  /// 渲染出来的实际行数（按每行文本框的顶端坐标去重，字面换行的真值）。
  int lineCount(WidgetTester tester) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(message));
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: message.length),
    );
    return boxes.map((box) => box.top.round()).toSet().length;
  }

  /// 浅底深字：浮层底色亮、字色暗（两者亮度差撑得起对比）。
  void expectLightSurfaceDarkText(WidgetTester tester, String label) {
    final material = tester.widget<Material>(find.byKey(hintKey));
    final background = material.color;
    expect(background, isNotNull, reason: '$label 浮层必须有底色');
    expect(
      background!.computeLuminance(),
      greaterThan(0.5),
      reason: '$label 浮层底色必须是浅色面',
    );
    final text = tester.widget<Text>(find.text(message));
    final foreground = text.style?.color;
    expect(foreground, isNotNull, reason: '$label 提示文字必须有字色');
    expect(
      foreground!.computeLuminance(),
      lessThan(0.5),
      reason: '$label 提示文字必须是深色字',
    );
  }

  /// 位置与观感的公共断言：贴「名册」左侧、同高、不出屏、浅底深字、最多两行。
  void expectAnchoredLeft(
    WidgetTester tester, {
    required String label,
    required Size view,
  }) {
    expect(find.text(message), findsOneWidget);
    final hint = rectOf(tester, hintKey);
    final roster = rectOf(tester, rosterKey);

    expect(
      hint.right,
      lessThanOrEqualTo(roster.left),
      reason: '$label 下浮层必须完全在「名册」钮左侧',
    );
    // 同高：浮层自锚点上沿起、落在锚点的竖向区间内。
    expect(
      hint.top,
      greaterThanOrEqualTo(roster.top - 0.5),
      reason: '$label 下浮层不得高过「名册」钮上沿（免得探进上一行）',
    );
    expect(
      hint.top,
      lessThanOrEqualTo(roster.bottom + 0.5),
      reason: '$label 下浮层必须与「名册」钮同高',
    );
    expect(hint.left, greaterThanOrEqualTo(0));
    expect(hint.top, greaterThanOrEqualTo(0));
    expect(hint.right, lessThanOrEqualTo(view.width));
    expect(hint.bottom, lessThanOrEqualTo(view.height));

    expectLightSurfaceDarkText(tester, label);
    expect(lineCount(tester), lessThanOrEqualTo(2), reason: '$label 最多两行');

    // 不压暗、无高亮框与气泡。
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
  }

  // 竖屏：备注输入框在上行、「名册」在下一行——键盘升起（触发条件）时，
  // 左侧同高的浮层不得压住正在打字的输入框。合成档 421×912dp 与宽窗口合成档
  // 800×1400dp 各取一次，名册空 / 非空各取一次（词条区改的是下行动作行的宽度）。
  // 两个都是合成档：421×912dp 与 800×1400dp，非设备档。
  for (final view in const [Size(421, 912), Size(800, 1400)]) {
    for (final dancers in const [0, 2]) {
      testWidgets('竖屏 $view（名册 $dancers 人）：键盘升起后提示贴「名册」左侧、同高、不压输入框', (
        tester,
      ) async {
        final storage = InMemoryPrivateJsonStorage();
        final container = await pumpHost(
          tester,
          storage: storage,
          view: view,
          keyboardInset: 336,
          dancers: dancers,
        );

        seedAndOpenNoteEditor(container);
        await tester.pumpAndSettle();

        expectAnchoredLeft(
          tester,
          label: '竖屏 ${view.width.toInt()}',
          view: view,
        );
        expect(
          rectOf(
            tester,
            hintKey,
          ).overlaps(rectOf(tester, const Key('note_text_editor_field'))),
          isFalse,
          reason: '竖屏下浮层不得压住正在打字的输入框',
        );

        // 显示过即置位（落盘），不等 4 秒走完。
        await tester.pump(const Duration(milliseconds: 100));
        expect((storage.snapshot['onboarding'] as Map)['badgeRoster'], isTrue);
      });
    }
  }

  // 横屏：编辑器是一条横排——输入框（Expanded）与「名册」之间只有收缩的
  // 舞者词条区（空名册时为零宽）。因此「贴锚点左侧」与「不压输入框」在横屏
  // 无法同时成立；取左侧同高（不压输入框只在竖屏成立）。
  for (final view in const [Size(912, 421), Size(1400, 800)]) {
    for (final dancers in const [0, 2]) {
      testWidgets('横屏 $view（名册 $dancers 人）：提示贴「名册」左侧、同高、不出屏、浅底深字', (
        tester,
      ) async {
        final storage = InMemoryPrivateJsonStorage();
        final container = await pumpHost(
          tester,
          storage: storage,
          view: view,
          keyboardInset: 180,
          dancers: dancers,
        );

        seedAndOpenNoteEditor(container);
        await tester.pumpAndSettle();

        expectAnchoredLeft(
          tester,
          label: '横屏 ${view.width.toInt()}',
          view: view,
        );
      });
    }
  }

  testWidgets('提示在场时不吞点击：名册钮照常可点、输入框照常可用', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final container = await pumpHost(
      tester,
      storage: storage,
      view: const Size(421, 912), // 合成档 421×912dp，非设备档。
      keyboardInset: 336,
    );

    seedAndOpenNoteEditor(container);
    await tester.pumpAndSettle();

    // 名册钮照常可点（原地换装到名册态）。
    await tester.tap(find.byKey(rosterKey));
    await tester.pump();
    expect(find.text('返回备注编辑'), findsOneWidget);

    // 输入框照常可用：点击聚焦后能输入。
    await tester.enterText(
      find.byKey(const Key('note_editor_dancer_field')),
      '果',
    );
    expect(find.text('果'), findsOneWidget);
  });

  testWidgets('约 4 秒自散；第二次打开备注编辑器不再出现', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final container = await pumpHost(
      tester,
      storage: storage,
      view: const Size(421, 912), // 合成档 421×912dp，非设备档。
      keyboardInset: 336,
    );

    seedAndOpenNoteEditor(container);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);

    // 约 4 秒后自己消失，无需任何操作。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);

    // 第二次写备注：不出现（显示过即置位）。
    container.read(noteTextEditorTargetProvider.notifier).close();
    await tester.pumpAndSettle();
    seedAndOpenNoteEditor(container);
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect((storage.snapshot['onboarding'] as Map)['badgeRoster'], isTrue);
  });

  testWidgets('重置后再回到触发点会再演一次', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final container = await pumpHost(
      tester,
      storage: storage,
      view: const Size(421, 912), // 合成档 421×912dp，非设备档。
      keyboardInset: 336,
    );

    seedAndOpenNoteEditor(container);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);

    // 重置该单元：只清状态位，不演出任何东西。
    await container.read(guideResetProvider).resetUnit(badgeRosterUnitId);
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);

    // 回到触发点（关掉再打开备注编辑器）：再演一次。
    container.read(noteTextEditorTargetProvider.notifier).close();
    await tester.pumpAndSettle();
    seedAndOpenNoteEditor(container);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
  });
}
