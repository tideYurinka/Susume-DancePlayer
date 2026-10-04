import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/about/about_page.dart';
import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/home/dance_detail_page.dart';
import 'package:dance_learning_app/home/prep_settings_page.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/import/video_importer.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show
        screenBrightnessControllerProvider,
        systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/update/update_check.dart';
import 'package:dance_learning_app/update/update_gateway.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:dance_learning_app/dance/cover_generation_queue.dart';
import 'package:dance_learning_app/dance/video_copy_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cover_cache.dart';
import '../helpers/device_viewport.dart';
import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';
import '../helpers/fake_update_gateway.dart';
import '../helpers/fake_video_picker.dart';
import '../helpers/fake_video_copy_presence.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/semantics_assertions.dart';

/// 首页舞库卡片流部件测试：沿用仓内页面级 pump 形态 + 既有内存
/// 替身装配 provider，断言卡片字段、排序、空态与两条点击接线。算术不在
/// 本层重复断言（快照口径归纯件直测）。
void main() {
  testWidgets('卡片字段与排序与快照一致：练过的在前，没练过的按导入次序尾排', (tester) async {
    // 放大视口：三张卡两行同屏，才能按位置断言整库次序（网格懒建）。
    tester.view.physicalSize = const Size(1000, 2200); // 合成档 1000×2200dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final today = DateTime.now();
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2'), _entry('v3')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            signature: const SongSignature(dancer: '如', song: '真值名'),
            rangeStartMs: 10000,
            rangeEndMs: 120000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
          ),
          local: const LocalDocument(
            mastery: {
              0: LearningMastery.keepingUp,
              1: LearningMastery.keepingUp,
            },
          ),
        ),
      },
      records: [
        PracticeSessionRecord(
          start: DateTime(today.year, today.month, today.day, 10),
          videoId: 'v1',
          signature: const SongSignature(song: 's'),
          wallSeconds: 180,
        ),
      ],
    );
    await harness.pump(tester);

    expect(find.byType(Card), findsNWidgets(3));
    // 署名真值优先，未署名回退文件名；百分比进封面内信息条。
    expect(_inCard('v1', '「如」真值名'), findsOneWidget);
    expect(_inCard('v1', '50%'), findsOneWidget);
    // 练习总时长与最近练习不再上卡片。
    expect(_inCard('v1', '练习 3:00'), findsNothing);
    expect(_inCard('v1', '最近 今天'), findsNothing);
    expect(find.byKey(const Key('dance_card_practice_v1')), findsNothing);
    // 每张卡底部有「查看详情」详情行。
    expect(_inCard('v1', '查看详情'), findsOneWidget);
    expect(find.byKey(const Key('dance_card_detail_v1')), findsOneWidget);
    // 未全段最高档：不出完全掌握勾。
    expect(find.byKey(const Key('dance_card_mastered_v1')), findsNothing);
    // 每个卡片都有封面占位图。
    for (final videoId in const ['v1', 'v2', 'v3']) {
      expect(find.byKey(Key('dance_cover_$videoId')), findsOneWidget);
    }

    // 排序 = 快照次序（本页不重排）：练过的 v1 最前；没练过的按导入次序
    // 倒序尾排（v3 在 v2 前）。两列错落按估算高度分配：同高时 v1 左、v3 右、
    // v2 落回左列 v1 之下。
    expect(
      tester.getTopLeft(find.byKey(const Key('dance_card_v1'))).dy,
      moreOrLessEquals(
        tester.getTopLeft(find.byKey(const Key('dance_card_v3'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('dance_card_v1'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('dance_card_v3'))).dx),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('dance_card_v3'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('dance_card_v2'))).dy),
    );
    // v1 与 v2 同属左列（v2 在 v3 之后落回较矮的左列）。
    expect(
      tester.getTopLeft(find.byKey(const Key('dance_card_v1'))).dx,
      moreOrLessEquals(
        tester.getTopLeft(find.byKey(const Key('dance_card_v2'))).dx,
      ),
    );
  });

  testWidgets('封面内信息条：百分比与已练遍数合成一行，占位图上有渐变暗底', (tester) async {
    tester.view.physicalSize = const Size(360, 800); // 合成档 360×800dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final today = DateTime.now();
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeStartMs: 10000,
            rangeEndMs: 130000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
          ),
          local: const LocalDocument(
            mastery: {
              0: LearningMastery.keepingUp,
              1: LearningMastery.keepingUp,
            },
          ),
        ),
      },
      records: [
        PracticeSessionRecord(
          start: DateTime(today.year, today.month, today.day, 10),
          videoId: 'v1',
          signature: const SongSignature(song: 's'),
          wallSeconds: 180,
        ),
      ],
    );
    await harness.pump(tester);

    // 180s ÷ 120s = 1.5 遍；两项在封面内同一行。
    expect(_inCard('v1', '50%'), findsOneWidget);
    expect(_inCard('v1', '已练 1.5 遍'), findsOneWidget);
    expect(_inCard('v1', '·'), findsOneWidget);
    expect(
      tester.getTopLeft(_inCard('v1', '已练 1.5 遍')).dy,
      moreOrLessEquals(tester.getTopLeft(_inCard('v1', '50%')).dy, epsilon: 1),
      reason: '百分比与已练遍数合成一行',
    );

    // 渐变暗底压在封面下半（占位图上也生效），信息条落在其底部左侧。
    final coverTop = tester
        .getTopLeft(find.byKey(const Key('dance_cover_v1')))
        .dy;
    final coverHeight = tester
        .getSize(find.byKey(const Key('dance_cover_v1')))
        .height;
    final gradient = find.byKey(const Key('dance_cover_gradient_v1'));
    expect(gradient, findsOneWidget);
    expect(tester.getSize(gradient).height, closeTo(coverHeight * 0.5, 1));
    expect(
      tester.getBottomRight(gradient).dy,
      moreOrLessEquals(coverTop + coverHeight, epsilon: 1),
      reason: '渐变暗底贴住封面底缘',
    );
    expect(
      tester.getTopLeft(_inCard('v1', '50%')).dy,
      greaterThan(coverTop + coverHeight / 2),
      reason: '信息条在封面下半部的暗底上',
    );
    // 信息条是封面内的白字（渐变暗底之上）。
    final infoStyle = tester.widget<Text>(_inCard('v1', '50%')).style;
    expect(infoStyle!.color, Colors.white);
  });

  testWidgets('无有效区间（未落盘 / 零长）：卡片不出遍数段，两项都缺则整行不出现', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      documents: {
        // v1 无文档 = 有效区间未落盘；v2 有效区间零长。
        'v2': _documents(
          markers: const MarkersDocument(rangeStartMs: 5000, rangeEndMs: 5000),
          local: const LocalDocument.empty(),
        ),
      },
    );
    await harness.pump(tester);

    expect(find.byKey(const Key('dance_card_average_v1')), findsNothing);
    expect(find.byKey(const Key('dance_card_average_v2')), findsNothing);
    expect(_inCard('v1', '—'), findsNothing);
    // 缺数据不冒充零。
    expect(_inCard('v1', '已练 0 遍'), findsNothing);
    expect(_inCard('v2', '已练 0 遍'), findsNothing);
    // v1/v2 都没标注：百分比与遍数都不出现，信息条整行不渲染。
    expect(find.byKey(const Key('dance_card_cover_info_v1')), findsNothing);
    expect(find.byKey(const Key('dance_card_cover_info_v2')), findsNothing);
  });

  testWidgets('信息条单段：没标注但有有效区间时只显已练遍数，不出百分比与分隔符', (tester) async {
    final today = DateTime.now();
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        // 无分段线（无百分比）但有有效区间（出遍数）。
        'v1': _documents(
          markers: const MarkersDocument(
            rangeStartMs: 10000,
            rangeEndMs: 130000,
          ),
          local: const LocalDocument.empty(),
        ),
      },
      records: [
        PracticeSessionRecord(
          start: DateTime(today.year, today.month, today.day, 10),
          videoId: 'v1',
          signature: const SongSignature(song: 's'),
          wallSeconds: 180,
        ),
      ],
    );
    await harness.pump(tester);

    expect(_averageText(tester, 'v1'), '已练 1.5 遍');
    expect(find.byKey(const Key('dance_card_percent_v1')), findsNothing);
    expect(_inCard('v1', '%'), findsNothing);
    expect(_inCard('v1', '·'), findsNothing);
  });

  testWidgets('没标注 / 没练过的舞：无百分比、无完成勾、零时长、无最近练习', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester);

    // 未署名卡片标题 = 「文件名回落名」（去扩展名）。
    expect(_inCard('v1', 'v1'), findsOneWidget);
    expect(find.byKey(const Key('dance_card_percent_v1')), findsNothing);
    expect(find.byKey(const Key('dance_card_mastered_v1')), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    // 没练过也没有时长与最近练习（这些不再上卡片）。
    expect(_inCard('v1', '练习 0:00'), findsNothing);
    expect(_inCard('v1', '还没练过'), findsNothing);
    // 没标注也没有有效区间：封面信息条整行不出现。
    expect(find.byKey(const Key('dance_card_cover_info_v1')), findsNothing);
    expect(find.byKey(const Key('dance_cover_v1')), findsOneWidget);
  });

  testWidgets('全段最高档：完成勾收进角标槽，卡片出 100%', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeStartMs: 10000,
            rangeEndMs: 120000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
          ),
          local: const LocalDocument(
            mastery: {0: LearningMastery.mastered, 1: LearningMastery.mastered},
          ),
        ),
      },
    );
    await harness.pump(tester);

    expect(
      find.byKey(const Key('dance_card_badge_mastered_v1')),
      findsOneWidget,
    );
    // 完成勾收进角标槽：副信息不再重复渲染同一事实。
    expect(find.byKey(const Key('dance_card_mastered_v1')), findsNothing);
    expect(_inCard('v1', '100%'), findsOneWidget);
  });

  testWidgets('DDL 逾期：卡片出红色逾期角标并置顶', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200); // 合成档 1000×2200dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final today = DateTime.now();
    DateTime day(int offset) => DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: offset));
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      planEntries: {
        'v2': {
          'videoId': 'v2',
          'ddl': {'date': planDayKey(day(-1))},
        },
      },
    );
    await harness.pump(tester);

    expect(
      find.byKey(const Key('dance_card_badge_overdue_v2')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('dance_card_badge_near_v2')), findsNothing);
    // 逾期置顶：v2 占左列首位，无目标的 v1 落右列。
    expect(
      tester.getTopLeft(find.byKey(const Key('dance_card_v2'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('dance_card_v1'))).dx),
    );
  });

  testWidgets('剩余 2 天：出临期角标；无目标未掌握：无角标', (tester) async {
    final today = DateTime.now();
    DateTime day(int offset) => DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: offset));
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      planEntries: {
        'v2': {
          'videoId': 'v2',
          'ddl': {'date': planDayKey(day(2))},
        },
      },
    );
    await harness.pump(tester);

    expect(find.byKey(const Key('dance_card_badge_near_v2')), findsOneWidget);
    expect(find.byKey(const Key('dance_card_badge_overdue_v2')), findsNothing);
    expect(find.byKey(const Key('dance_card_badge_mastered_v2')), findsNothing);
    expect(find.byKey(const Key('dance_card_badge_overdue_v1')), findsNothing);
    expect(find.byKey(const Key('dance_card_badge_near_v1')), findsNothing);
    expect(find.byKey(const Key('dance_card_badge_mastered_v1')), findsNothing);
  });

  testWidgets('完全掌握勾收进角标槽：副信息不再重复出勾', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeStartMs: 10000,
            rangeEndMs: 120000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
          ),
          local: const LocalDocument(
            mastery: {0: LearningMastery.mastered, 1: LearningMastery.mastered},
          ),
        ),
      },
    );
    await harness.pump(tester);

    expect(
      find.byKey(const Key('dance_card_badge_mastered_v1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('dance_card_mastered_v1')), findsNothing);
    expectSemanticsLabel(
      tester,
      const Key('dance_card_badge_mastered_v1'),
      label: '已完全掌握',
      reason: '卡片角标同样要报出真值（与舞详情、计划管理页同款）',
    );
    expect(_inCard('v1', '100%'), findsOneWidget);
  });

  testWidgets('点封面或标题打开该舞续播；详情行整行进舞详情（不抢同一次点按）', (tester) async {
    useNamedViewport(tester, ViewportTier.compact);
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester);

    // 点标题 → 续播。
    await tester.tap(find.byKey(const Key('dance_card_title_v1')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(
      harness.engine.source!.toFilePath(),
      '/videos/v1.mp4',
      reason: '卡片标题打开的是这条索引条目的视频副本（续播语义归播放器侧）',
    );
    harness.navigator(tester).pop();
    await tester.pumpAndSettle();

    // 点封面 → 续播。
    await tester.tap(find.byKey(const Key('dance_card_open_v1')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byType(DanceDetailPage), findsNothing);
    harness.navigator(tester).pop();
    await tester.pumpAndSettle();

    // 点详情行（行首空白处，不瞄准箭头）→ 舞详情，不打开播放。
    final rowTopLeft = tester.getTopLeft(
      find.byKey(const Key('dance_card_detail_v1')),
    );
    await tester.tapAt(rowTopLeft + const Offset(4, 12));
    await tester.pumpAndSettle();

    expect(find.byType(DanceDetailPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DanceDetailPage),
        matching: find.text('继续播放'),
      ),
      findsOneWidget,
    );
    expect(find.byType(PlayerPage), findsNothing, reason: '详情行与卡片主体不抢同一次点按');
  });

  testWidgets('副本丢失：卡片带丢失标记、点开进找回面而不是播放页、也不排队取帧', (tester) async {
    useNamedViewport(tester, ViewportTier.compact);
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      copyPresence: FakeVideoCopyPresence(
        missingPaths: const {'/videos/v1.mp4'},
      ),
    );
    await harness.pump(tester);

    // 只有副本不在的那张卡带标记。
    expect(find.byKey(const Key('dance_card_copy_missing_v1')), findsOneWidget);
    expect(find.byKey(const Key('dance_card_copy_missing_v2')), findsNothing);
    // 丢失期间不可用：封面取帧不排队（在场的舞照常排队）。
    expect(
      [for (final request in harness.coverRunner.requested) request.videoId],
      ['v2'],
    );

    // 点开丢失的舞：进找回面，不进播放页。
    await tester.tap(find.byKey(const Key('dance_card_open_v1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_recovery_page')), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);

    // 副本在场的舞照旧进播放页。
    harness.navigator(tester).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_card_open_v2')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
  });

  testWidgets('空库：空态可达导入（导入入口常驻）', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);

    expect(find.byKey(const Key('dance_library_empty')), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.byKey(const Key('import_video_button')), findsOneWidget);
    expect(find.byKey(const Key('stats_entry_button')), findsNothing);
  });

  testWidgets('首页入口：浮动钮只有「导入视频」，⋯菜单有「备份」与「恢复备份」', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);

    expect(find.byKey(const Key('import_video_button')), findsOneWidget);
    expect(
      find.byKey(const Key('import_scheme_button')),
      findsNothing,
      reason: '选包入口收敛到 ⋯ 菜单，浮动钮不再有',
    );

    await tester.tap(find.byKey(const Key('home_more_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup_menu_item')), findsOneWidget);
    expect(find.byKey(const Key('restore_backup_menu_item')), findsOneWidget);
  });

  testWidgets('⋯菜单「详细设置」可达：点后进入设备级设置页', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);

    await tester.tap(find.byKey(const Key('home_more_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_menu_item')));
    await tester.pumpAndSettle();

    expect(find.byType(PrepSettingsPage), findsOneWidget);
    expect(find.text('预备拍数'), findsOneWidget);
  });

  testWidgets('⋯菜单在现有三项之后多出「关于」：点后打开关于页', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);

    await tester.tap(find.byKey(const Key('home_more_menu')));
    await tester.pumpAndSettle();

    final aboutItem = find.byKey(const Key('about_menu_item'));
    expect(aboutItem, findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('settings_menu_item'))).dy,
      lessThan(tester.getTopLeft(aboutItem).dy),
      reason: '「关于」排在「详细设置」之后',
    );

    await tester.tap(aboutItem);
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('关于')),
      findsOneWidget,
    );
  });

  testWidgets('导入完成回到首页：索引已落盘，新卡出现', (tester) async {
    final harness = _Harness();
    final importer = _StubImporter(
      storage: harness.indexStorage,
      entry: _entry('v1'),
      imported: _importedVideo('v1'),
    );
    harness.importer = importer;
    await harness.pump(tester);

    expect(find.byKey(const Key('dance_library_empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('import_video_button')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);

    // 导入返回时条目已在册（见 VideoImporter）：从播放器回到首页即出新卡。
    harness.navigator(tester).pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_library_empty')), findsNothing);
    // 未署名卡片标题 = 「文件名回落名」（去扩展名）。
    expect(_inCard('v1', 'v1'), findsOneWidget);
  });

  testWidgets('导入返回即索引就绪：立刻回首页，新卡当场出现（首页不再轮询等落盘）', (tester) async {
    final harness = _Harness();
    final importer = _StubImporter(
      storage: harness.indexStorage,
      entry: _entry('v1'),
      imported: _importedVideo('v1'),
    );
    harness.importer = importer;
    await harness.pump(tester);

    await tester.tap(find.byKey(const Key('import_video_button')));
    await tester.pumpAndSettle();
    // 不额外等任何时限、不手工补落索引：回首页即出现。
    harness.navigator(tester).pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_library_empty')), findsNothing);
    // 未署名卡片标题 = 「文件名回落名」（去扩展名）。
    expect(_inCard('v1', 'v1'), findsOneWidget);
  });

  testWidgets('读面未就绪：加载态与错误态都保留常驻导入入口', (tester) async {
    final loading = _Harness(indexStore: _HangingIndexStorage());
    await loading.pump(tester);
    expect(find.text('加载中…'), findsOneWidget);
    expect(find.byKey(const Key('import_video_button')), findsOneWidget);

    final failing = _Harness(indexStore: _FailingIndexStorage());
    await failing.pump(tester);
    expect(find.text('舞库读取失败'), findsOneWidget);
    expect(find.byKey(const Key('import_video_button')), findsOneWidget);
  });

  testWidgets('练完回到首页：读面照常重算，练习总时长与最近练习仍不上卡片', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        // 已有节拍数据：打开这一趟不触发分析/自动分段改写区间。
        'v1': _documents(
          markers: _markersWithBeat(rangeStartMs: 10000, rangeEndMs: 130000),
          local: const LocalDocument.empty(),
        ),
      },
    );
    await harness.pump(tester);

    expect(_inCard('v1', '已练 0 遍'), findsOneWidget);
    expect(_inCard('v1', '练习 0:00'), findsNothing);
    expect(_inCard('v1', '还没练过'), findsNothing);

    await tester.tap(find.byKey(const Key('dance_card_open_v1')));
    await tester.pumpAndSettle();

    // 会话期间练了 3 分钟（练舞统计落盘），模拟练完返回首页。
    final today = DateTime.now();
    await harness.statsStore.recordPlaying(
      videoId: 'v1',
      signature: const SongSignature(song: 's'),
      start: DateTime(today.year, today.month, today.day, 10),
      end: DateTime(today.year, today.month, today.day, 10, 3),
    );
    await harness.statsStore.settle();

    harness.navigator(tester).pop();
    await tester.pumpAndSettle();

    // 读面重算了（已练遍数随统计刷新），但时长与最近练习不再渲染。
    expect(_inCard('v1', '已练 1.5 遍'), findsOneWidget);
    expect(_inCard('v1', '练习 3:00'), findsNothing);
    expect(_inCard('v1', '最近 今天'), findsNothing);
    expect(find.byKey(const Key('dance_card_v1')), findsOneWidget);
  });

  testWidgets('一行标题的卡片比两行标题的矮（卡片高度随标题行数变化）', (tester) async {
    tester.view.physicalSize = const Size(360, 800); // 合成档 360×800dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String longTitle() => '长' * 40; // 远超两行
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      documents: {
        'v1': _documents(
          markers: const MarkersDocument(
            signature: SongSignature(dancer: '如', song: '短名'),
          ),
          local: LocalDocument.empty(),
        ),
        'v2': _documents(
          markers: MarkersDocument(
            signature: SongSignature(dancer: '如', song: longTitle()),
          ),
          local: LocalDocument.empty(),
        ),
      },
    );
    await harness.pump(tester);

    final shortCard = tester.getSize(find.byKey(const Key('dance_card_v1')));
    final longCard = tester.getSize(find.byKey(const Key('dance_card_v2')));
    expect(find.byKey(const Key('dance_card_title_v1')), findsOneWidget);
    // 同比例封面下，两行标题的卡比一行标题的高。
    expect(longCard.height, greaterThan(shortCard.height));
    // 两张卡分落两列（错落仍在）。
    expect(
      tester.getTopLeft(find.byKey(const Key('dance_card_v1'))).dx,
      isNot(
        moreOrLessEquals(
          tester.getTopLeft(find.byKey(const Key('dance_card_v2'))).dx,
        ),
      ),
    );
  });

  testWidgets('两列错落按卡片真实高度平衡：标题行数参与估算', (tester) async {
    tester.view.physicalSize = const Size(360, 800); // 合成档 360×800dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 三张横屏封面（同比例）：首张标题超两行、其余一行。练过的 v1 排最前。
    // v1 → 左列；v3（矮）→ 右列；v2 落回当时较矮的右列。
    // 若标题高度不参与估算（三张同高），v2 会被分进左列。
    final today = DateTime.now();
    SongSignature sig(String song) => SongSignature(dancer: '如', song: song);
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2'), _entry('v3')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(signature: sig('长' * 40)),
          local: LocalDocument.empty(),
        ),
      },
      coverCache: InMemoryCoverCache(
        ready: {'v1', 'v2', 'v3'},
        aspectRatios: const {'v1': 4 / 3, 'v2': 4 / 3, 'v3': 4 / 3},
        positions: const {
          'v1': Duration.zero,
          'v2': Duration.zero,
          'v3': Duration.zero,
        },
      ),
      records: [
        PracticeSessionRecord(
          start: DateTime(today.year, today.month, today.day, 10),
          videoId: 'v1',
          signature: sig('长' * 40),
          wallSeconds: 60,
        ),
      ],
    );
    await harness.pump(tester);

    final v1Dx = tester.getTopLeft(find.byKey(const Key('dance_card_v1'))).dx;
    final v2Dx = tester.getTopLeft(find.byKey(const Key('dance_card_v2'))).dx;
    final v3Dx = tester.getTopLeft(find.byKey(const Key('dance_card_v3'))).dx;
    expect(v1Dx, lessThan(v3Dx), reason: 'v1（长标题）在左列');
    expect(v3Dx, moreOrLessEquals(v2Dx), reason: 'v2 与 v3 同在右列');
    expect(
      tester.getTopLeft(find.byKey(const Key('dance_card_v2'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('dance_card_v3'))).dy),
      reason: 'v2 落在 v3 之下（右列当时更矮）',
    );
  });

  testWidgets('就绪卡片渲染真封面；未就绪显示 3:4 占位', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      coverCache: InMemoryCoverCache(
        ready: {'v1'},
        aspectRatios: {'v1': 4 / 3},
        positions: {'v1': Duration.zero},
      ),
    );
    await harness.pump(tester);

    // v1 就绪：真图渲染、无占位图、封面框按图片自身的 4:3。
    expect(find.byKey(const Key('dance_cover_image_v1')), findsOneWidget);
    expect(find.byKey(const Key('dance_cover_placeholder_v1')), findsNothing);
    expect(_coverRatio(tester, 'v1'), closeTo(4 / 3, 1e-9));

    // v2 未就绪：占位图、无真图、封面框按 3:4 占位。
    expect(find.byKey(const Key('dance_cover_image_v2')), findsNothing);
    expect(find.byKey(const Key('dance_cover_placeholder_v2')), findsOneWidget);
    expect(_coverRatio(tester, 'v2'), closeTo(3 / 4, 1e-9));
  });

  testWidgets('竖屏 3:4、横屏 4:3：卡片高度随封面比例变化（错落）', (tester) async {
    tester.view.physicalSize = const Size(360, 800); // 合成档 360×800dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      coverCache: InMemoryCoverCache(
        ready: {'v1', 'v2'},
        aspectRatios: {'v1': 3 / 4, 'v2': 4 / 3},
        positions: {'v1': Duration.zero, 'v2': Duration.zero},
      ),
    );
    await harness.pump(tester);

    expect(_coverRatio(tester, 'v1'), closeTo(3 / 4, 1e-9));
    expect(_coverRatio(tester, 'v2'), closeTo(4 / 3, 1e-9));
    // 竖屏封面更高：整张卡明显高于同宽横屏卡（高度随比例变化）。
    expect(
      tester.getSize(find.byKey(const Key('dance_card_v1'))).height,
      greaterThan(
        tester.getSize(find.byKey(const Key('dance_card_v2'))).height + 40,
      ),
    );
    // 两列错落：两张卡落在不同列。
    expect(
      tester.getTopLeft(find.byKey(const Key('dance_card_v1'))).dx,
      isNot(
        moreOrLessEquals(
          tester.getTopLeft(find.byKey(const Key('dance_card_v2'))).dx,
        ),
      ),
    );
  });

  testWidgets('进入可见区才排队取帧；完成后该卡自动换成真图', (tester) async {
    tester.view.physicalSize = const Size(360, 330); // 合成档 360×330dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = _Harness(
      index: VideoIndex(
        entries: [_entry('v1'), _entry('v2'), _entry('v3'), _entry('v4')],
      ),
    );
    harness.coverRunner.blocked = true;
    await harness.pump(tester);

    // 未练组按导入次序倒序（v4 最前）；同高竖屏占位下首行两张可见、
    // 第二行两张在视口外——只有可见的两张入队。
    expect(
      [for (final request in harness.coverRunner.requested) request.videoId],
      ['v4', 'v3'],
    );
    // 取帧入队时用的是该舞的副本路径与封面位置（默认跟随首线 = 第 0 帧）。
    expect(harness.coverRunner.requested.first.sourcePath, '/videos/v4.mp4');
    expect(harness.coverRunner.requested.first.position, Duration.zero);

    // 滚动后第二行两张进入可见区并入队；同时最多两条在飞，故先挂在队列里
    // （不至多起解码进程）。避开右下浮动钮的命中区再拖。
    await tester.dragFrom(const Offset(60, 120), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(harness.coverRunner.requested, hasLength(2));

    // 放行首行两张：排队的第二行按进入可见区的次序依次起步。
    await harness.coverCache.writeFrom(
      'v4',
      File('/in-memory/v4'),
      Duration.zero,
    );
    harness.coverRunner.release('v4', ready: true);
    harness.coverRunner.release('v3', ready: false);
    await tester.pumpAndSettle();
    expect(
      [for (final request in harness.coverRunner.requested) request.videoId],
      ['v4', 'v3', 'v2', 'v1'],
    );

    // 完成 v4 取帧并落进缓存：该卡自动换成真图，其余仍是占位图。
    expect(find.byKey(const Key('dance_cover_image_v4')), findsOneWidget);
    expect(find.byKey(const Key('dance_cover_placeholder_v4')), findsNothing);
    expect(find.byKey(const Key('dance_cover_placeholder_v3')), findsOneWidget);
  });

  testWidgets('首线改动：位置变了旧封面作废，按新首线重新排队取帧', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: _markersWithBeat(rangeStartMs: 10000, rangeEndMs: 120000),
          local: const LocalDocument.empty(),
        ),
      },
      coverCache: InMemoryCoverCache(
        ready: {'v1'},
        aspectRatios: {'v1': 3 / 4},
        positions: {'v1': const Duration(seconds: 10)},
      ),
    );
    await harness.pump(tester);
    expect(find.byKey(const Key('dance_cover_image_v1')), findsOneWidget);

    // 用户改了首线（10s → 20s）后回到首页：读面重算，旧图不再算就绪。
    await harness.documents['v1']!.saveMarkers(
      _markersWithBeat(rangeStartMs: 20000, rangeEndMs: 120000).toJson(),
    );
    await tester.tap(find.byKey(const Key('dance_card_open_v1')));
    await tester.pumpAndSettle();
    harness.navigator(tester).pop();
    await tester.pumpAndSettle();

    // 位置变了：旧图作废回占位图，并按新首线位置重新排队。
    expect(find.byKey(const Key('dance_cover_placeholder_v1')), findsOneWidget);
    expect(harness.coverRunner.requested, hasLength(1));
    expect(
      harness.coverRunner.requested.single.position,
      const Duration(seconds: 20),
    );
  });

  testWidgets('首线改动但新位置已有缓存：直接换新图，不停在占位', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: _markersWithBeat(rangeStartMs: 10000, rangeEndMs: 120000),
          local: const LocalDocument.empty(),
        ),
      },
      coverCache: InMemoryCoverCache(
        ready: {'v1'},
        aspectRatios: {'v1': 3 / 4},
        positions: {'v1': const Duration(seconds: 10)},
      ),
    );
    await harness.pump(tester);
    expect(find.byKey(const Key('dance_cover_image_v1')), findsOneWidget);

    // 新首线位置已有缓存就绪：读面重算后卡片直接接上新图。
    await harness.coverCache.writeFrom(
      'v1',
      File('/in-memory/v1'),
      const Duration(seconds: 20),
    );
    await harness.documents['v1']!.saveMarkers(
      _markersWithBeat(rangeStartMs: 20000, rangeEndMs: 120000).toJson(),
    );
    await tester.tap(find.byKey(const Key('dance_card_open_v1')));
    await tester.pumpAndSettle();
    harness.navigator(tester).pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_cover_image_v1')), findsOneWidget);
    expect(find.byKey(const Key('dance_cover_placeholder_v1')), findsNothing);
  });

  testWidgets('本会话已取过封面后首线再改：按新位置重新取帧并换新图与新比例', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: _markersWithBeat(rangeStartMs: 10000, rangeEndMs: 120000),
          local: const LocalDocument.empty(),
        ),
      },
      // 该舞的封面是横屏 4:3（读面只知 3:4 占位，比例要等取到图才更新）。
      coverCache: InMemoryCoverCache(aspectRatios: {'v1': 4 / 3}),
    );
    harness.coverRunner.blocked = true;
    await harness.pump(tester);

    // 首线帧（10s）入队取帧 → 就绪后卡片换真图与真比例。
    expect(
      harness.coverRunner.requested.single.position,
      const Duration(seconds: 10),
    );
    await harness.coverCache.writeFrom(
      'v1',
      File('/in-memory/v1'),
      const Duration(seconds: 10),
    );
    harness.coverRunner.release('v1', ready: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_cover_image_v1')), findsOneWidget);
    expect(_coverRatio(tester, 'v1'), closeTo(4 / 3, 1e-9));

    // 首线改到 20s 后回首页：旧结果不能复用，必须按新位置再取一次。
    await harness.documents['v1']!.saveMarkers(
      _markersWithBeat(rangeStartMs: 20000, rangeEndMs: 120000).toJson(),
    );
    await tester.tap(find.byKey(const Key('dance_card_open_v1')));
    await tester.pumpAndSettle();
    harness.navigator(tester).pop();
    await tester.pumpAndSettle();

    expect(harness.coverRunner.requested, hasLength(2));
    expect(
      harness.coverRunner.requested.last.position,
      const Duration(seconds: 20),
    );
    // 读面仍按 3:4 占位（新位置未就绪），取到图后卡片按图片自身 4:3 渲染。
    expect(find.byKey(const Key('dance_cover_placeholder_v1')), findsOneWidget);
    await harness.coverCache.writeFrom(
      'v1',
      File('/in-memory/v1'),
      const Duration(seconds: 20),
    );
    harness.coverRunner.release('v1', ready: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_cover_image_v1')), findsOneWidget);
    expect(_coverRatio(tester, 'v1'), closeTo(4 / 3, 1e-9));
  });

  testWidgets('导入路径不取帧：停在播放器时零请求，回首页卡片可见才排队', (tester) async {
    final harness = _Harness();
    final importer = _StubImporter(
      storage: harness.indexStorage,
      entry: _entry('v1'),
      imported: _importedVideo('v1'),
    );
    harness.importer = importer;
    await harness.pump(tester);

    await tester.tap(find.byKey(const Key('import_video_button')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);

    // 导入（条目随导入返回已在册）不成封面：导入路径不做任何取帧。
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(harness.coverRunner.requested, isEmpty);

    // 回到首页、新卡进入可见区，惰性取帧才排队。
    harness.navigator(tester).pop();
    await tester.pumpAndSettle();
    expect(
      [for (final request in harness.coverRunner.requested) request.videoId],
      ['v1'],
    );
  });
}

/// 卡片封面框的宽高比。
double _coverRatio(WidgetTester tester, String videoId) => tester
    .widget<AspectRatio>(find.byKey(Key('dance_cover_$videoId')))
    .aspectRatio;

/// 卡片内文本（卡片上的字段各自落点断言用）。
Finder _inCard(String videoId, String text) => find.descendant(
  of: find.byKey(Key('dance_card_$videoId')),
  matching: find.text(text),
);

/// 卡片「已练遍数」栏位的文案（按键定位，不靠整卡文本撞）。
String? _averageText(WidgetTester tester, String videoId) =>
    tester.widget<Text>(find.byKey(Key('dance_card_average_$videoId'))).data;

class _Harness {
  _Harness({
    VideoIndex index = VideoIndex.empty,
    VideoIndexStorage? indexStore,
    this.documents = const {},
    this.planEntries,
    List<PracticeSessionRecord> records = const [],
    InMemoryCoverCache? coverCache,
    VideoCopyPresence? copyPresence,
  }) : indexStorage = indexStore ?? InMemoryVideoIndexStorage(initial: index),
       statsStorage = InMemoryPracticeStatsStorage(),
       coverCache = coverCache ?? InMemoryCoverCache(),
       copyPresence = copyPresence ?? FakeVideoCopyPresence(),
       engine = FakePlaybackEngine() {
    if (records.isNotEmpty) {
      statsStorage.rawJson = PracticeStatsDocument(sessions: records).toJson();
    }
    statsStore = PracticeStatsStore(statsStorage);
    coverRunner = _FakeCoverRunner();
  }

  final VideoIndexStorage indexStorage;
  final InMemoryPracticeStatsStorage statsStorage;
  final FakePlaybackEngine engine;
  late final PracticeStatsStore statsStore;

  /// 封面缓存替身（默认一份封面也没有 = 卡片先出占位图）。
  final InMemoryCoverCache coverCache;

  /// 副本存在性替身（缺省 = 副本都在场；丢失用例喂假）。
  final VideoCopyPresence copyPresence;

  /// 取帧队列的执行替身：记录请求（可见优先次序）；默认不取帧。
  late final _FakeCoverRunner coverRunner;

  /// 导入替身（仅在需要跑导入回首页的用例里装配）。
  VideoImporter? importer;

  /// 每支舞的两份文档（缺省 = 无文档 = 未标注）。
  final Map<String, InMemoryVideoDocumentStorage> documents;

  /// 计划文档条目（videoId → 条目 JSON；null = 无计划文档）。
  final Map<String, Map<String, dynamic>>? planEntries;

  Future<void> pump(WidgetTester tester) async {
    final planStorage = InMemoryPracticePlanStorage();
    if (planEntries != null) {
      planStorage.rawJson = {
        'version': 1,
        'entries': [for (final entry in planEntries!.values) entry],
      };
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practicePlanStorageProvider.overrideWithValue(planStorage),
          videoIndexStoreProvider.overrideWithValue(indexStorage),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => documents[videoId] ?? InMemoryVideoDocumentStorage(),
          ),
          coverCacheProvider.overrideWith((ref) => coverCache),
          videoCopyPresenceProvider.overrideWithValue(copyPresence),
          coverGenerationQueueProvider.overrideWith(
            (ref) => CoverGenerationQueue(run: coverRunner.run),
          ),
          practiceStatsStoreProvider.overrideWithValue(statsStore),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(
              initial: const {
                'onboarding': {'firstRun': true},
              },
            ),
          ),
          fourBeatBucketStoreProvider.overrideWithValue(
            FourBeatBucketStore(InMemoryFourBeatBucketStorage()),
          ),
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          screenBrightnessControllerProvider.overrideWithValue(
            FakeScreenBrightnessController(),
          ),
          systemMediaVolumeControllerProvider.overrideWithValue(
            FakeSystemMediaVolumeController(),
          ),
          // 更新网关与本机构建号是网络/平台读面：整壳用例喂确定的替身，不让
          // 根壳的启动检查卡在真实平台上（关于页版本行会因此停在「无法检查更新」）。
          updateGatewayProvider.overrideWithValue(FakeUpdateGateway()),
          localBuildNumberProvider.overrideWith((ref) async => 1),
          if (importer != null)
            videoImporterProvider.overrideWithValue(importer!),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  NavigatorState navigator(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator));
}

/// 取帧执行替身：记录请求（断言可见优先次序与导入路径不取帧）；[blocked]
/// 时把请求挂在队列里由用例显式放行，便于断言并发与「就绪后自动换图」。
class _FakeCoverRunner {
  final List<CoverFrameRequest> requested = [];
  bool blocked = false;
  bool succeeds = false;
  final Map<String, Completer<bool>> _gates = {};

  Future<bool> run(CoverFrameRequest request) {
    requested.add(request);
    if (!blocked) return Future.value(succeeds);
    final gate = Completer<bool>();
    _gates[request.videoId] = gate;
    return gate.future;
  }

  void release(String videoId, {required bool ready}) =>
      _gates[videoId]!.complete(ready);
}

/// 导入替身：真实导入链的文件复制与摘要计算在 fake async 时钟下不可完成，
/// 故只替换 [VideoImporter.import]；其余构造参数取一用即报错的桩——真走回
/// 真实管道时立刻失败，不静默写进临时目录。
///
/// [import] 照实模拟导入的返回时点：条目**随返回即在册**（票 #15 的同步落盘
/// 语义），因此首页不需要任何「等后台落盘」的等待。
class _StubImporter extends VideoImporter {
  _StubImporter({
    required VideoIndexStorage storage,
    required this.entry,
    required this.imported,
  }) : _storage = storage,
       super(
         FakeVideoPicker(null),
         () async => throw StateError('导入替身不走复制路径'),
         indexStore: storage,
         hasher: const FixedHasher('stub'),
       );

  final VideoIndexStorage _storage;
  final VideoIndexEntry entry;
  final ImportedVideo imported;

  @override
  Future<ImportedVideo?> import() async {
    await _storage.update((index) => index.upsert(entry));
    return imported;
  }
}

/// 永不返回的索引存储：首页停在加载态。
class _HangingIndexStorage implements VideoIndexStorage {
  @override
  Future<VideoIndex> load() => Completer<VideoIndex>().future;

  @override
  Future<VideoIndex> update(
    FutureOr<VideoIndex> Function(VideoIndex current) mutate,
  ) async => throw UnimplementedError();
}

/// 读即失败的索引存储：首页停在错误态。
class _FailingIndexStorage implements VideoIndexStorage {
  @override
  Future<VideoIndex> load() async => throw StateError('索引不可读');

  @override
  Future<VideoIndex> update(
    FutureOr<VideoIndex> Function(VideoIndex current) mutate,
  ) async => throw UnimplementedError();
}

ImportedVideo _importedVideo(String videoId) => ImportedVideo(
  name: '$videoId.mp4',
  uri: File('/videos/$videoId.mp4').uri,
  sizeBytes: 1,
);

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  mirrorAsked: true,
  lastOpenedAt: DateTime(2026, 9, 1),
);

InMemoryVideoDocumentStorage _documents({
  required MarkersDocument markers,
  required LocalDocument local,
}) => InMemoryVideoDocumentStorage(
  markers: markers.toJson(),
  local: local.toJson(),
);

/// 已有节拍数据的公开标记文件：打开这支舞不触发后台分析/自动分段，故
/// 「打开→回首页」这一趟不改盘上的区间与分段（封面位置等读取面照原样可断言）。
MarkersDocument _markersWithBeat({
  required int rangeStartMs,
  required int rangeEndMs,
}) => MarkersDocument(rangeStartMs: rangeStartMs, rangeEndMs: rangeEndMs)
    .withBeat(
      BeatGrid(
        model: 'madmom_downbeat_rnn_full.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2026, 9, 1),
        beats: const [
          BeatPoint(t: 0.5, down: true),
          BeatPoint(t: 1.0, down: false),
        ],
      ),
    );
