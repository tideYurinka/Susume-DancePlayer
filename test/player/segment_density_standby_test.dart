import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show
        BeatTrackState,
        BeatTrackStateModel,
        beatTrackStateProvider,
        beatGridProvider,
        committedBeatGridProvider;
import 'package:dance_learning_app/core/beat_grid.dart' show BeatGrid;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationEditorProvider,
        annotationMemberSchemeReadonlyProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        segmentDensitiesProvider,
        selectedLearningSegmentRangeProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/annotation_edit.dart'
    show AddSegmentLine;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart'
    show AnnotationSaveSink, AnnotationSectionDiff;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/beat_density_panel.dart'
    show BeatDensityBubbleContent;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/segment_density_grid_wiring.dart'
    show beatGridSegmentContextWiring;
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/pump_past_marquee.dart';
import '../helpers/video_index_fixtures.dart';

/// 记录 diff 的假保存编排（只读拒绝、无写入断言用）。
class RecordingSink implements AnnotationSaveSink {
  final diffs = <AnnotationSectionDiff>[];

  @override
  void save(AnnotationSectionDiff diff) => diffs.add(diff);

  @override
  Future<void> flush() async {}
}

/// 固定节拍轨状态（置灰两态注入用）。
class FixedBeatTrackState extends BeatTrackStateModel {
  FixedBeatTrackState(this.value);
  final BeatTrackState value;

  @override
  BeatTrackState build() => value;
}

/// 段内倍频待命态的进出与前置：
///
/// - 入口：节拍倍频气泡内「对特定段落设置倍频」按下即**关气泡 + 落待办**
///   （经播放会话模式唯一进入路径）进待命态；置灰门 = 真实拍点可用
///   （占位/异常置灰并沿用该面板既有的使用提示句式）。
/// - 待命态：工具槽整排换装为三枚赋值钮 + 退出；退出钮无门恒可点；无
///   选中时三钮置灰但按得动、弹既有「无对象」做法文案；一条分段都没有时
///   弹「先用『分段』或『自动分段』切出段来」。
/// - 点轨道学习段 = 选中并循环（沿用学习段选中的点选；循环范围由选中
///   派生）。待命态是编辑面取值，轨道交互与编辑态同一套。
/// - 退出三路（退出钮 / 收起控制层）与组员方案只读（进入无前置、数据
///   逐位不变）。
void main() {
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    AnnotationSaveSink? sink,
    bool readyBeat = true,
  }) async {
    final resolved = Uri.file('/videos/a.mp4');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          beatGridSegmentContextWiring,
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          if (sink != null) annotationSaveSinkProvider.overrideWithValue(sink),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(
              initial: VideoIndex(
                entries: [
                  historyEntry(filePath: resolved.toFilePath(), mirrored: false),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp(home: PlayerPage(source: resolved)),
      ),
    );
    await tester.pumpAndSettle();
    if (readyBeat) {
      await injectBeatState(
        tester,
        uniformDownbeatBeatState(
          seconds:
              (engine.duration ?? const Duration(seconds: 60)).inMilliseconds /
              1000,
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

  /// 打开节拍倍频气泡并按下「对特定段落设置倍频」（回调直调：回调本身即
  /// 生产接线）。控制层展开后标题跑幕动画常驻——用 [pumpPastMarquee]。
  Future<void> pressSegmentEntry(WidgetTester tester) async {
    containerOf(tester)
        .read(speedBubbleSessionProvider.notifier)
        .open(SpeedBubbleMode.beatDensity);
    await tester.pumpAndSettle();
    tester
        .widget<OutlinedButton>(
          find.byKey(const Key('beat_density_segment_entry')),
        )
        .onPressed!();
    await pumpPastMarquee(tester);
  }

  /// 落两条分段线（经标注编辑模块唯一写缝）。
  void seedSegments(ProviderContainer container) {
    final editor = container.read(annotationEditorProvider);
    editor.submit(const AddSegmentLine(at: Duration(seconds: 10)));
    editor.submit(const AddSegmentLine(at: Duration(seconds: 20)));
  }

  /// 点第一段的段体（与 control_layer_test 同款命中点）。
  Future<void> tapFirstSegmentBody(WidgetTester tester) async {
    final rect = tester.getRect(find.byKey(const Key('learning_segment_0')));
    await tester.tapAt(
      Offset(rect.left + rect.width * 0.25, rect.top + rect.height * 0.75),
    );
    await tester.pumpAndSettle();
  }

  bool slotTappable(WidgetTester tester, String slotKey) =>
      tester
          .widget<InkWell>(
            find
                .descendant(
                  of: find.byKey(Key(slotKey)),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .onTap !=
      null;

  Finder noSubjectPrompt(String text) => find.descendant(
    of: find.byKey(const Key('no_subject_prompt')),
    matching: find.text(text),
  );

  void expectGrayed(WidgetTester tester, String hint) {
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('beat_density_segment_entry')),
          )
          .onPressed,
      isNull,
      reason: '$hint：入口置灰',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('beat_density_segment_entry_hint')),
          )
          .data,
      hint,
    );
  }

  testWidgets('气泡内入口存在；按下关气泡 + 经待办进段内倍频待命态，工具槽换装', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    await pumpPlayer(tester, engine: engine);

    containerOf(
      tester,
    ).read(speedBubbleSessionProvider.notifier).open(SpeedBubbleMode.beatDensity);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('beat_density_segment_entry')), findsOneWidget);

    await pressSegmentEntry(tester);

    expect(
      containerOf(tester).read(playerSessionProvider).mode,
      PlayerSessionMode.segmentDensityStandby,
    );
    expect(containerOf(tester).read(playerSessionProvider).pendingEntry,
        isNull, reason: '宿主编排后待办清空');
    expect(containerOf(tester).read(speedBubbleSessionProvider).open, isNull,
        reason: '按下即关气泡（互斥单开）');
    expect(find.byKey(const Key('beat_density_bubble')), findsNothing);
    for (final key in [
      'control_segment_density_faster',
      'control_segment_density_slower',
      'control_segment_density_reset',
      'control_segment_density_exit',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: '待命态槽集换装');
    }
    expect(find.byKey(const Key('control_mastery')), findsNothing,
        reason: '整排换装：原标注工具槽不显示');
  });

  testWidgets('置灰门：占位（分析中/未开始）入口置灰并按既有句式说明原因', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(
            FakePlaybackEngine(duration: const Duration(seconds: 30)),
          ),
          beatTrackStateProvider.overrideWith(
            () => FixedBeatTrackState(const BeatTrackState.placeholder()),
          ),
        ],
        child: const MaterialApp(home: BeatDensityBubbleContent()),
      ),
    );
    await tester.pump();
    expectGrayed(tester, '节拍分析完成后可用');
  });

  testWidgets('置灰门：异常态入口置灰并按既有句式说明原因', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(
            FakePlaybackEngine(duration: const Duration(seconds: 30)),
          ),
          beatTrackStateProvider.overrideWith(
            () => FixedBeatTrackState(const BeatTrackState.error()),
          ),
        ],
        child: const MaterialApp(home: BeatDensityBubbleContent()),
      ),
    );
    await tester.pump();
    expectGrayed(tester, '节拍识别失败，暂不可用');
  });

  testWidgets('无选中：三枚赋值钮置灰但按得动，点一下弹「先点一段再点这里」、不落盘', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final sink = RecordingSink();
    await pumpPlayer(tester, engine: engine, sink: sink);
    seedSegments(containerOf(tester));
    sink.diffs.clear();
    await pressSegmentEntry(tester);

    expect(
      containerOf(tester).read(selectedLearningSegmentsProvider),
      isEmpty,
    );
    expect(slotTappable(tester, 'control_segment_density_faster'), isTrue,
        reason: '无对象 → 置灰但按得动');
    expect(slotTappable(tester, 'control_segment_density_slower'), isTrue);
    expect(slotTappable(tester, 'control_segment_density_reset'), isTrue);

    await tester.tap(find.byKey(const Key('control_segment_density_faster')));
    await tester.pump();
    await tester.pump();
    expect(noSubjectPrompt('先点一段再点这里'), findsOneWidget);
    expect(sink.diffs, isEmpty, reason: '动作不发生、不落盘');
  });

  testWidgets('一条分段线都没有：点赋值钮弹「先用『分段』或『自动分段』切出段来」', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    await pumpPlayer(tester, engine: engine);
    expect(containerOf(tester).read(annotationTimelineProvider).segmentLines,
        isEmpty);

    await pressSegmentEntry(tester);
    await tester.tap(find.byKey(const Key('control_segment_density_reset')));
    await tester.pump();
    await tester.pump();
    expect(noSubjectPrompt('先用『分段』或『自动分段』切出段来'), findsOneWidget);
  });

  testWidgets('待命态点轨道学习段 = 选中并循环（循环范围由选中段派生）', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    await pumpPlayer(tester, engine: engine);
    seedSegments(containerOf(tester));
    await pressSegmentEntry(tester);

    expect(containerOf(tester).read(selectedLearningSegmentsProvider), isEmpty);
    expect(
      containerOf(tester).read(selectedLearningSegmentRangeProvider),
      isNull,
      reason: '进入即从「无选中」开始',
    );

    await tapFirstSegmentBody(tester);

    expect(
      containerOf(tester).read(selectedLearningSegmentsProvider),
      isNotEmpty,
      reason: '点学习段即选中（待命态是编辑面取值，点选沿用）',
    );
    expect(
      containerOf(tester).read(selectedLearningSegmentRangeProvider),
      isNotNull,
      reason: '选中的段立即循环（循环范围 = 选中段合并范围）',
    );
  });

  testWidgets('退出钮无门恒可点：按下回编辑面（控制层仍展开）、不改文档', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final sink = RecordingSink();
    await pumpPlayer(tester, engine: engine, sink: sink);
    seedSegments(containerOf(tester));
    sink.diffs.clear();
    await pressSegmentEntry(tester);

    expect(slotTappable(tester, 'control_segment_density_exit'), isTrue,
        reason: '退出钮不声明任何门、待命态内恒可点');

    await tester.tap(find.byKey(const Key('control_segment_density_exit')));
    await tester.pump();

    expect(
      containerOf(tester).read(playerSessionProvider).mode,
      PlayerSessionMode.editing,
      reason: '退待命 = 进入编辑取值，控制层仍展开',
    );
    expect(find.byKey(const Key('control_mastery')), findsOneWidget,
        reason: '工具槽恢复编辑态槽集');
    expect(sink.diffs, isEmpty, reason: '退出钮不改文档');
  });

  testWidgets('收起控制层退出待命态回观看态；组员方案只读下进入无前置、全程零写入', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final sink = RecordingSink();
    await pumpPlayer(tester, engine: engine, sink: sink);
    seedSegments(containerOf(tester));
    sink.diffs.clear();
    final container = containerOf(tester);
    final timelineBefore = container.read(annotationTimelineProvider);

    container
        .read(annotationMemberSchemeReadonlyProvider.notifier)
        .setLoaded(true);

    // 只读组员方案下入口照常进入（待命态无进入前置），改动被既有只读门禁
    // 拦下：全程无一次落盘。
    await pressSegmentEntry(tester);
    expect(
      container.read(playerSessionProvider).mode,
      PlayerSessionMode.segmentDensityStandby,
    );

    container.read(playerSessionProvider.notifier).collapse();
    await tester.pump();

    expect(container.read(playerSessionProvider).mode,
        PlayerSessionMode.watching, reason: '收起控制层 = 退出待命态');
    expect(container.read(annotationTimelineProvider), timelineBefore,
        reason: '退出后我的数据逐位相同');
    expect(sink.diffs, isEmpty, reason: '组员方案只读：任何改动被静默拒绝');

    // 返回首页 / 换视频同走既有 reset 触发点（与八拍矫正同一退出机制，
    // 无手写退出点）：待命态内 reset 同样回观看态、数据不动。
    await pressSegmentEntry(tester);
    expect(container.read(playerSessionProvider).mode,
        PlayerSessionMode.segmentDensityStandby);
    container.read(playerSessionProvider.notifier).reset();
    await tester.pump();
    expect(container.read(playerSessionProvider).mode,
        PlayerSessionMode.watching);
    expect(container.read(annotationTimelineProvider), timelineBefore);
    expect(sink.diffs, isEmpty);
  });

  // ── ：三枚赋值钮与多段作用域 ──

  testWidgets('赋值语义：快一倍连按两次仍 ×2（不叠乘）、慢一半设 ×½、回到原样删键；各自一步撤销', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final sink = RecordingSink();
    await pumpPlayer(tester, engine: engine, sink: sink);
    seedSegments(containerOf(tester));
    sink.diffs.clear();
    final container = containerOf(tester);
    Map<int, double> densities() => container.read(segmentDensitiesProvider);
    await pressSegmentEntry(tester);
    await tapFirstSegmentBody(tester);
    sink.diffs.clear();

    await tester.tap(find.byKey(const Key('control_segment_density_faster')));
    await tester.pumpAndSettle();
    expect(densities(), const {0: 2.0}, reason: '赋值：设为 ×2');
    expect(sink.diffs.length, 1, reason: '经既有标注编辑提交路径落盘');

    await tester.tap(find.byKey(const Key('control_segment_density_faster')));
    await tester.pumpAndSettle();
    expect(densities(), const {0: 2.0}, reason: '连按不叠乘（仍 ×2）');
    expect(sink.diffs.length, 1, reason: '同值赋值 = 无变化、不落盘');

    await tester.tap(find.byKey(const Key('control_segment_density_slower')));
    await tester.pumpAndSettle();
    expect(densities(), const {0: 0.5}, reason: '慢一半 = 设为 ×½（非相对步进）');

    container.read(annotationEditorProvider).undo();
    await tester.pumpAndSettle();
    expect(densities(), const {0: 2.0}, reason: '撤销一步回到 ×2');

    await tester.tap(find.byKey(const Key('control_segment_density_reset')));
    await tester.pumpAndSettle();
    expect(densities(), isEmpty, reason: '回到原样 = 设为 1（删键）');

    container.read(annotationEditorProvider).undo();
    await tester.pumpAndSettle();
    expect(densities(), const {0: 2.0}, reason: '删键也是一步撤销');
  });

  testWidgets('长按圈选两段后按一下「快一倍」：整片统一为 ×2（一个 diff、一步撤销）', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final sink = RecordingSink();
    await pumpPlayer(tester, engine: engine, sink: sink);
    seedSegments(containerOf(tester));
    sink.diffs.clear();
    final container = containerOf(tester);
    await pressSegmentEntry(tester);

    // 长按横拖一次圈起连着的两段（与 track_band_test 同款手势）。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('learning_segment_1'))),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(-600, 0));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(container.read(selectedLearningSegmentsProvider), const {0, 1});
    sink.diffs.clear();

    await tester.tap(find.byKey(const Key('control_segment_density_faster')));
    await tester.pumpAndSettle();

    expect(container.read(segmentDensitiesProvider), const {0: 2.0, 1: 2.0},
        reason: '一次作用于选中的全部段、整片统一为同一档');
    expect(sink.diffs.length, 1, reason: '一次改多段 = 一次标注编辑');

    container.read(annotationEditorProvider).undo();
    await tester.pumpAndSettle();
    expect(container.read(segmentDensitiesProvider), isEmpty,
        reason: '整片改动 = 一步撤销');
  });

  testWidgets('多段档位不一时按一下即整片统一为同一档（一个 diff、一步撤销）', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final sink = RecordingSink();
    await pumpPlayer(tester, engine: engine, sink: sink);
    seedSegments(containerOf(tester));
    final container = containerOf(tester);
    await pressSegmentEntry(tester);

    // 段 0 设 ×2，段 1 保持缺省：两段档位不一。
    await tapFirstSegmentBody(tester);
    await tester.tap(find.byKey(const Key('control_segment_density_faster')));
    await tester.pumpAndSettle();
    expect(container.read(segmentDensitiesProvider), const {0: 2.0});
    sink.diffs.clear();

    // 长按圈选两段，按一下「慢一半」：整片（含已是 ×2 的段）统一为 ×½。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('learning_segment_1'))),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(-600, 0));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(container.read(selectedLearningSegmentsProvider), const {0, 1});
    sink.diffs.clear();

    await tester.tap(find.byKey(const Key('control_segment_density_slower')));
    await tester.pumpAndSettle();
    expect(container.read(segmentDensitiesProvider), const {0: 0.5, 1: 0.5},
        reason: '档位不一按一下即整片统一（赋值覆盖，不叠乘）');
    expect(sink.diffs.length, 1, reason: '一次改多段 = 一次标注编辑');
    container.read(annotationEditorProvider).undo();
    await tester.pumpAndSettle();
    expect(container.read(segmentDensitiesProvider), const {0: 2.0},
        reason: '整片统一 = 一步撤销');
  });

  testWidgets('读数：显示选中段的段内档；多段档位不一时显示最小档；无选中不显示', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    await pumpPlayer(tester, engine: engine);
    seedSegments(containerOf(tester));
    final container = containerOf(tester);
    Finder readout() => find.byKey(const Key('segment_density_readout'));
    String? readoutText() => tester.widgetList<Text>(
          find.descendant(of: readout(), matching: find.textContaining('')),
        ).isEmpty
        ? null
        : tester
            .widget<Text>(
              find.descendant(of: readout(), matching: find.textContaining('')),
            )
            .data;

    await pressSegmentEntry(tester);
    expect(readout(), findsNothing, reason: '无选中不显示读数');

    // 段 0 设 ×2（档位不一时读数应取最小档 ×½，与熟练度槽显示最低档同先例）。
    await tapFirstSegmentBody(tester);
    await tester.tap(find.byKey(const Key('control_segment_density_faster')));
    await tester.pumpAndSettle();
    expect(container.read(segmentDensitiesProvider), const {0: 2.0});
    expect(readoutText(), '×2', reason: '读数显示选中段的段内档');

    // 段 1 设 ×½，再圈选两段：读数 = 最小档 ×½。
    await tester.tap(find.byKey(const Key('learning_segment_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('learning_segment_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('control_segment_density_slower')));
    await tester.pumpAndSettle();
    expect(container.read(segmentDensitiesProvider), const {0: 2.0, 1: 0.5});
    // 点选规则是单选/取消（不加选）：多段选中用长按圈选。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('learning_segment_1'))),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(-600, 0));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(container.read(selectedLearningSegmentsProvider), const {0, 1});
    expect(readoutText(), '×½', reason: '多段档位不一时显示最小档');
  });

  testWidgets('回到原样保持可点：选中段本来就全是原样时按下无变化、不弹提示', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final sink = RecordingSink();
    await pumpPlayer(tester, engine: engine, sink: sink);
    seedSegments(containerOf(tester));
    sink.diffs.clear();
    final container = containerOf(tester);
    await pressSegmentEntry(tester);
    await tapFirstSegmentBody(tester);
    sink.diffs.clear();
    expect(container.read(segmentDensitiesProvider), isEmpty);

    await tester.tap(find.byKey(const Key('control_segment_density_reset')));
    await tester.pumpAndSettle();

    expect(
      slotTappable(tester, 'control_segment_density_reset'),
      isTrue,
      reason: '全是原样时仍可点（与整曲档「重置」一致）',
    );
    expect(container.read(segmentDensitiesProvider), isEmpty,
        reason: '按下无变化');
    expect(sink.diffs, isEmpty, reason: '无变化不落盘');
    expect(
      tester.widgetList(find.byKey(const Key('no_subject_prompt'))),
      isEmpty,
      reason: '不弹「无对象」提示',
    );
  });

  testWidgets('按下即生效：派生网格实时跟随（段内拍距减半）、落盘网格与线的时刻不动；退出后值仍在盘上', (tester) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final sink = RecordingSink();
    await pumpPlayer(tester, engine: engine, sink: sink);
    seedSegments(containerOf(tester));
    sink.diffs.clear();
    final container = containerOf(tester);
    await pressSegmentEntry(tester);
    await tapFirstSegmentBody(tester);
    sink.diffs.clear();

    int beatsWithin(Duration bound, BeatGrid grid) {
      final last = grid.lastBeatIndex;
      var count = 0;
      for (var i = 0; last == null || i <= last; i++) {
        if (grid.beatTime(i) >= bound) break;
        count++;
      }
      return count;
    }

    final presentationBefore = beatsWithin(
      const Duration(seconds: 10),
      container.read(beatGridProvider),
    );
    final committedBefore = beatsWithin(
      const Duration(seconds: 10),
      container.read(committedBeatGridProvider),
    );
    final lineTimesBefore = container
        .read(annotationTimelineProvider)
        .segmentLines
        .map((line) => line.position)
        .toList();

    await tester.tap(find.byKey(const Key('control_segment_density_faster')));
    await tester.pumpAndSettle();

    final presentationAfter = beatsWithin(
      const Duration(seconds: 10),
      container.read(beatGridProvider),
    );
    expect(presentationBefore, 20, reason: '段内原拍距 0.5s');
    expect(presentationAfter, 40, reason: '段 ×2 后段内拍距 0.25s（刻度/数拍实时跟随）');
    expect(
      beatsWithin(
        const Duration(seconds: 10),
        container.read(committedBeatGridProvider),
      ),
      committedBefore,
      reason: '落盘网格（统计桶格来源）不接逐段档（负面契约）',
    );
    expect(
      container
          .read(annotationTimelineProvider)
          .segmentLines
          .map((line) => line.position),
      lineTimesBefore,
      reason: '倍频不移线',
    );

    // 退出待命态：已改的值留在盘上。
    await tester.tap(find.byKey(const Key('control_segment_density_exit')));
    await tester.pumpAndSettle();
    expect(container.read(playerSessionProvider).mode,
        PlayerSessionMode.editing);
    expect(container.read(segmentDensitiesProvider), const {0: 2.0},
        reason: '退出后已改的值仍在盘上');
    expect(sink.diffs, isNotEmpty, reason: '改动经保存编排落盘');

    // 退出三路同语义：收起控制层也不弃已改的值。
    container.read(playerSessionProvider.notifier).collapse();
    await tester.pumpAndSettle();
    expect(container.read(playerSessionProvider).mode,
        PlayerSessionMode.watching);
    expect(container.read(segmentDensitiesProvider), const {0: 2.0});
  });
}
