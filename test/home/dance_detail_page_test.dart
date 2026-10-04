import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/home/dance_detail_page.dart';
import 'package:dance_learning_app/home/practice_distribution_chart.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show practicePlanStorageProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show
        screenBrightnessControllerProvider,
        systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/scheme_open.dart'
    show AutoSchemeOpen, MemberSchemeOpen, MySchemeOpen;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/core/local_day.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_key.dart';
import 'package:dance_learning_app/stats/practice_stats_format.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cover_cache.dart';
import '../helpers/fake_cover_generator.dart';
import '../helpers/beat_test_seam.dart';
import '../helpers/device_viewport.dart';
import '../helpers/failing_video_document_storage.dart';
import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_brightness.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/fake_playback_engine.dart';

import 'dart:io';

import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/share/dance_share.dart';
import 'package:dance_learning_app/share/outbound_scheme_id.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';

import '../helpers/fake_share_channel.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/semantics_assertions.dart';

/// 舞详情页部件测试：页面只渲染舞库快照——断言总览四项、逐段
/// 列表与打开/续播接线；派生口径本身归 `test/dance/` 直测，本层不重算。
void main() {
  testWidgets('总览四项与快照一致；无有效区间时平均练习遍数显示 —', (tester) async {
    final today = DateTime.now();
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeStartMs: 10000,
            rangeEndMs: 130000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 70))],
          ),
          local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
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
    await harness.pump(tester, videoId: 'v1');

    // 练习总时长 3:00、最近练习今天、平均 180s ÷ 120s = 1.5 遍。
    expect(_value('dance_detail_total', '3:00'), findsOneWidget);
    expect(_value('dance_detail_last', '今天'), findsOneWidget);
    expect(_value('dance_detail_average', '1.5 遍'), findsOneWidget);
    // 未全段最高档：不出完成勾，如实显示 —。
    expect(_value('dance_detail_mastered', '—'), findsOneWidget);
    expectSemanticsLabel(
      tester,
      const Key('dance_detail_mastered'),
      label: '未完全掌握',
      reason: '破折号读不出「未」：读屏要分清是/未',
    );
  });

  testWidgets('无有效区间：平均练习遍数显示 —（不用整片时长凑假数）', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester, videoId: 'v1');

    expect(_value('dance_detail_total', '0:00'), findsOneWidget);
    expect(_value('dance_detail_last', '还没练过'), findsOneWidget);
    expect(_value('dance_detail_average', '—'), findsOneWidget);
    expect(_value('dance_detail_mastered', '—'), findsOneWidget);
  });

  testWidgets('全段最高档：总览出完全掌握勾', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeEndMs: 120000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
          ),
          local: const LocalDocument(
            mastery: {0: LearningMastery.mastered, 1: LearningMastery.mastered},
          ),
        ),
      },
    );
    await harness.pump(tester, videoId: 'v1');

    expect(
      find.descendant(
        of: find.byKey(const Key('dance_detail_mastered')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expectSemanticsLabel(
      tester,
      const Key('dance_detail_mastered'),
      label: '已完全掌握',
      reason: '真值不能只有对勾图标：读屏要报出「是」',
    );
  });

  testWidgets('逐段列表退场：段行、标题与「还没有分段」空态都不再出现', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeEndMs: 24000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
            beat: uniformDownbeatGridDoc(seconds: 24),
          ),
          local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
        ),
      },
      bucketStorage: _buckets({
        0: const FourBeatBucketValue(wallSeconds: 10, sweeps: 3),
      }),
    );
    await harness.pump(tester, videoId: 'v1');

    // 滚到页尾再滚回来：列表若还在，任何位置都该出现段行键。
    await _scrollToKey(tester, 'practice_distribution_card');
    expect(find.text('我的标注 · 逐段'), findsNothing);
    expect(find.text('还没有分段'), findsNothing);
    expect(find.byKey(const Key('dance_detail_no_segments')), findsNothing);
    expect(find.byKey(const Key('dance_segment_order_0')), findsNothing);
    expect(find.byKey(const Key('dance_segment_order_1')), findsNothing);
    expect(find.byKey(const Key('dance_segment_mastery_0')), findsNothing);
    expect(
      find.byKey(const Key('dance_segment_practice_duration_0')),
      findsNothing,
    );
    expect(find.byKey(const Key('dance_segment_no_beat_0')), findsNothing);
  });

  testWidgets('未落条目的舞：如实说明不在舞库（不展示空条目）', (tester) async {
    final harness = _Harness(index: VideoIndex.empty);
    await harness.pump(tester, videoId: 'v1');

    expect(find.byKey(const Key('dance_detail_missing')), findsOneWidget);
    expect(find.byKey(const Key('dance_detail_open')), findsNothing);
  });

  testWidgets('无标注的舞：不出段行；一键完全掌握入口在但置灰不可点；改名与删除入口在', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester, videoId: 'v1');

    // 顶部封面横幅占去首屏高度，分布图卡要滚到可见。
    await _scrollToKey(tester, 'dance_detail_master_all');
    // 「一键完全掌握」移到练习分布图卡片上。
    expect(
      find.ancestor(
        of: find.byKey(const Key('dance_detail_master_all')),
        matching: find.byKey(const Key('practice_distribution_card')),
      ),
      findsOneWidget,
    );
    // 改名与删除收进右上「⋯」：菜单里两项在；页尾不再有这两颗按钮。
    expect(find.byKey(const Key('dance_detail_more')), findsOneWidget);
    await _openMoreMenu(tester);
    expect(find.byKey(const Key('dance_detail_rename')), findsOneWidget);
    expect(find.byKey(const Key('dance_detail_delete')), findsOneWidget);
    await _dismissMoreMenu(tester);
    expect(find.byKey(const Key('dance_detail_rename')), findsNothing);
    expect(find.byKey(const Key('dance_detail_delete')), findsNothing);
    // 无分段线 = 无作用对象：入口在、置灰不可点（本按钮自己判 segments
    // 为空，不经标注工具槽判定表）。
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('dance_detail_master_all')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('dance_detail_master_all_undo')), findsNothing);

    // 按下去静默：不弹提示、什么也不发生。
    await tester.tap(find.byKey(const Key('dance_detail_master_all')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('底部按钮文案为「继续播放」，且页面上没有「打开续播」', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester, videoId: 'v1');

    expect(find.text('继续播放'), findsOneWidget);
    expect(find.text('打开续播'), findsNothing);
  });

  testWidgets('设备等效视口下 ⋯ 与改名/删除可达；页尾只剩「继续播放」', (tester) async {
    // compact 档（该次量测所用视口 = (1264×2736, 3.5) → 361.1×781.7dp）：
    // 可达性 ≠ 存在性，界面类判据在 compact 下按真手势断言。
    useNamedViewport(tester, ViewportTier.compact);

    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester, videoId: 'v1');

    // 页尾只剩「继续播放」一颗主钮；改名/删除按钮不在页面上。
    expect(find.byKey(const Key('dance_detail_open')), findsOneWidget);
    expect(find.text('继续播放'), findsOneWidget);
    expect(find.byKey(const Key('dance_detail_rename')), findsNothing);
    expect(find.byKey(const Key('dance_detail_delete')), findsNothing);

    // ⋯ 点得动：点开后菜单真展开（点后状态真的变）。
    await tester.tap(find.byKey(const Key('dance_detail_more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_detail_rename')), findsOneWidget);

    // 改名可达：这一按真的按到 → 命名弹窗出现。
    await tester.tap(find.byKey(const Key('dance_detail_rename')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('naming_skip')));
    await tester.pumpAndSettle();

    // 删除可达：菜单重开后点到删除 → 确认弹窗出现。
    await tester.tap(find.byKey(const Key('dance_detail_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_detail_delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_delete_dialog')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_delete_dialog')), findsNothing);
    expect(harness.indexStorage.current.findById('v1'), isNotNull);
  });

  testWidgets('一键完全掌握：全部段置最高档，详情出完成勾、卡片百分比与勾随写后快照更新', (tester) async {
    final storage = _documents(
      markers: MarkersDocument(
        rangeEndMs: 24000,
        segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
      ),
      local: const LocalDocument(mastery: {0: LearningMastery.familiar}),
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': storage},
    );
    await harness.pumpHome(tester);
    expect(_cardText('v1', '38%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dance_card_detail_v1')));
    await tester.pumpAndSettle();
    // 按钮在练习分布图卡片上，滚到可见再按。
    await _scrollToKey(tester, 'dance_detail_master_all');
    await tester.tap(find.byKey(const Key('dance_detail_master_all')));
    await tester.pumpAndSettle();

    // 全部段最高档（落盘）+ 总览完成勾。
    expect(LocalDocument.fromJson(storage.localSnapshot).mastery, const {
      0: LearningMastery.mastered,
      1: LearningMastery.mastered,
    });
    expect(
      find.descendant(
        of: find.byKey(const Key('dance_detail_mastered')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );

    // 返回首页：卡片百分比与完成勾随写后快照更新（没重开页面）。
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_cardText('v1', '100%'), findsOneWidget);
    expect(
      find.byKey(const Key('dance_card_badge_mastered_v1')),
      findsOneWidget,
    );
  });

  testWidgets('撤销：一键完全掌握后回写快照，回到点击前的值', (tester) async {
    final storage = _documents(
      markers: MarkersDocument(
        rangeEndMs: 24000,
        segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
      ),
      local: const LocalDocument(mastery: {0: LearningMastery.familiar}),
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': storage},
    );
    await harness.pump(tester, videoId: 'v1');

    await _scrollToKey(tester, 'dance_detail_master_all');
    await tester.tap(find.byKey(const Key('dance_detail_master_all')));
    await tester.pumpAndSettle();
    expect(LocalDocument.fromJson(storage.localSnapshot).mastery, const {
      0: LearningMastery.mastered,
      1: LearningMastery.mastered,
    });

    await tester.tap(find.byKey(const Key('dance_detail_master_all_undo')));
    await tester.pumpAndSettle();

    // 段 0 回「较熟」、段 1 回「未练」（稀疏：原为未练的段清出 Map）。
    expect(LocalDocument.fromJson(storage.localSnapshot).mastery, const {
      0: LearningMastery.familiar,
    });
    expect(find.byKey(const Key('dance_detail_master_all_undo')), findsNothing);
  });

  testWidgets('重复点击一键完全掌握：撤销仍回到最初点击前的值', (tester) async {
    final storage = _documents(
      markers: MarkersDocument(
        rangeEndMs: 24000,
        segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
      ),
      local: const LocalDocument(mastery: {0: LearningMastery.familiar}),
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': storage},
    );
    await harness.pump(tester, videoId: 'v1');

    // 连点两次：快照只记第一次点击之前，不被「已全掌握」覆盖。
    await _scrollToKey(tester, 'dance_detail_master_all');
    await tester.tap(find.byKey(const Key('dance_detail_master_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_detail_master_all')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dance_detail_master_all_undo')));
    await tester.pumpAndSettle();

    expect(LocalDocument.fromJson(storage.localSnapshot).mastery, const {
      0: LearningMastery.familiar,
    });
  });

  testWidgets('一键完全掌握写失败：如实告知、读面不重算（无撤销入口）', (tester) async {
    final inner = _documents(
      markers: MarkersDocument(
        rangeEndMs: 24000,
        segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
      ),
      local: const LocalDocument(mastery: {0: LearningMastery.familiar}),
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': inner},
      storageFactory: (id) => id == 'v1'
          ? FailingVideoDocumentStorage(inner, failLocal: true)
          : InMemoryVideoDocumentStorage(),
    );
    await harness.pump(tester, videoId: 'v1');

    await _scrollToKey(tester, 'dance_detail_master_all');
    await tester.tap(find.byKey(const Key('dance_detail_master_all')));
    await tester.pumpAndSettle();

    expect(find.text('改档失败'), findsOneWidget);
    expect(find.byKey(const Key('dance_detail_master_all_undo')), findsNothing);
    expect(LocalDocument.fromJson(inner.localSnapshot).mastery, const {
      0: LearningMastery.familiar,
    });
  });

  testWidgets('删除入口：二次确认存在且默认不删（取消后索引与文档原样）', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester, videoId: 'v1');

    await _openMoreMenu(tester);
    await tester.tap(find.byKey(const Key('dance_detail_delete')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_delete_dialog')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_delete_dialog')), findsNothing);
    expect(harness.indexStorage.current.findById('v1'), isNotNull);
    expect(find.byKey(const Key('dance_detail_open')), findsOneWidget);
  });

  testWidgets('改名：三字段保留现值、保存后详情即时显示新名并双写两条', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: const MarkersDocument(
            signature: SongSignature(dancer: '如', song: '旧名', remark: '9人版'),
          ),
          local: const LocalDocument.empty(),
        ),
      },
    );
    await harness.pump(tester, videoId: 'v1');
    expect(find.widgetWithText(AppBar, '「如」旧名 - 9人版'), findsOneWidget);

    await _openMoreMenu(tester);
    await tester.tap(find.byKey(const Key('dance_detail_rename')));
    await tester.pumpAndSettle();

    // 改名预填现值（三字段保留、不静默清空舞者/注记）。
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('naming_song_field')))
          .controller!
          .text,
      '旧名',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('naming_dancer_field')))
          .controller!
          .text,
      '如',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('naming_remark_field')))
          .controller!
          .text,
      '9人版',
    );

    // 改歌名、清空注记（版本注记可选）：保存后详情标题即时生效。
    await tester.enterText(find.byKey(const Key('naming_song_field')), '新名');
    await tester.enterText(find.byKey(const Key('naming_remark_field')), '');
    await tester.pump();
    await tester.tap(find.byKey(const Key('naming_save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('song_naming_dialog')), findsNothing);
    expect(find.widgetWithText(AppBar, '「如」新名'), findsOneWidget);
    // 两条都写：署名真值（markers）+ 索引署名缓存。
    expect(
      MarkersDocument.fromJson(harness.documents['v1']!.markersSnapshot)
          .signature,
      const SongSignature(dancer: '如', song: '新名'),
    );
    expect(
      harness.indexStorage.current.entries.single.signatureCache,
      const SongSignature(dancer: '如', song: '新名'),
    );
  });

  testWidgets('改名跳过：署名保持原样', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: const MarkersDocument(signature: SongSignature(song: '旧名')),
          local: const LocalDocument.empty(),
        ),
      },
    );
    await harness.pump(tester, videoId: 'v1');

    await _openMoreMenu(tester);
    await tester.tap(find.byKey(const Key('dance_detail_rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('naming_song_field')), '改一半');
    await tester.pump();
    await tester.tap(find.byKey(const Key('naming_skip')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '旧名'), findsOneWidget);
    expect(
      MarkersDocument.fromJson(harness.documents['v1']!.markersSnapshot)
          .signature,
      const SongSignature(song: '旧名'),
    );
  });

  testWidgets('署名真值写失败：提示「改名失败」，详情仍是旧名', (tester) async {
    final inner = _documents(
      markers: const MarkersDocument(signature: SongSignature(song: '旧名')),
      local: const LocalDocument.empty(),
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': inner},
      storageFactory: (id) => id == 'v1'
          ? FailingVideoDocumentStorage(inner, failMarkers: true)
          : InMemoryVideoDocumentStorage(),
    );
    await harness.pump(tester, videoId: 'v1');

    await _openMoreMenu(tester);
    await tester.tap(find.byKey(const Key('dance_detail_rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('naming_song_field')), '新名');
    await tester.tap(find.byKey(const Key('naming_save')));
    await tester.pumpAndSettle();

    expect(find.text('改名失败'), findsOneWidget);
    expect(find.widgetWithText(AppBar, '旧名'), findsOneWidget);
    expect(
      MarkersDocument.fromJson(inner.markersSnapshot).signature,
      const SongSignature(song: '旧名'),
      reason: '真值没写成：公开标记文件原样',
    );
  });

  testWidgets('改名后卡片与详情同显新名（无需重开）', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: const MarkersDocument(signature: SongSignature(song: '旧名')),
          local: const LocalDocument.empty(),
        ),
      },
    );
    await harness.pumpHome(tester);
    expect(_cardText('v1', '旧名'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dance_card_detail_v1')));
    await tester.pumpAndSettle();
    await _openMoreMenu(tester);
    await tester.tap(find.byKey(const Key('dance_detail_rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('naming_song_field')), '新名');
    await tester.tap(find.byKey(const Key('naming_save')));
    await tester.pumpAndSettle();

    // 详情在场即时看到新名。
    expect(find.widgetWithText(AppBar, '新名'), findsOneWidget);

    // 返回首页：卡片同源快照，也是新名（没重开页面）。
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_cardText('v1', '新名'), findsOneWidget);
    expect(_cardText('v1', '旧名'), findsNothing);
  });

  testWidgets('打开续播：与卡片主体同一打开语义；练完回详情刷新读面', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester, videoId: 'v1');

    expect(_value('dance_detail_total', '0:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dance_detail_open')));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(
      harness.engine.source!.toFilePath(),
      '/videos/v1.mp4',
      reason: '打开的是这条索引条目的视频副本（续播位置与「从头播放？」归播放器侧）',
    );

    // 会话期间练了 3 分钟，返回详情后读面重算。
    final today = DateTime.now();
    await harness.statsStore.recordPlaying(
      videoId: 'v1',
      signature: const SongSignature(song: 's'),
      start: DateTime(today.year, today.month, today.day, 10),
      end: DateTime(today.year, today.month, today.day, 10, 3),
    );
    await harness.statsStore.settle();

    // 播放页无标准返回钮，走系统返回通道（与真实退出路径一致）。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(_value('dance_detail_total', '3:00'), findsOneWidget);
    expect(_value('dance_detail_last', '今天'), findsOneWidget);
  });
  testWidgets('组员方案区：列出组员名、来源、导入时间、熟练度快照，与我的标注区分', (tester) async {
    final memberStorage = await _schemesStorage([
      MemberSchemeRecord(
        schemeId: 's1',
        memberName: '小如',
        schemeName: '队长版',
        mastery: const {0: 4, 1: 2},
        importedAt: DateTime(2026, 9, 10),
      ),
      MemberSchemeRecord(
        schemeId: 's9',
        memberName: '',
        schemeName: '',
        importedAt: DateTime(2026, 9, 10),
      ),
    ]);
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      memberStorage: memberStorage,
    );
    await harness.pump(tester, videoId: 'v1');

    await _scrollToKey(tester, 'dance_scheme_row_s1');
    expect(_schemeText('dance_scheme_member_s1', '小如的方案'), findsOneWidget);
    expect(_schemeText('dance_scheme_source_s1', '来源 队长版'), findsOneWidget);
    expect(
      _schemeText(
        'dance_scheme_time_s1',
        '导入 ${dayLabel(DateTime(2026, 9, 10), now: DateTime.now())}',
      ),
      findsOneWidget,
    );
    expect(
      _schemeText('dance_scheme_mastery_s1', '熟练度快照 掌握×1 · 能跟上×1'),
      findsOneWidget,
    );
    // 缺署名回落「未署名」；缺方案名不出「来源」行。
    await _scrollToKey(tester, 'dance_scheme_row_s9');
    expect(_schemeText('dance_scheme_member_s9', '未署名的方案'), findsOneWidget);
    expect(find.byKey(const Key('dance_scheme_source_s9')), findsNothing);
    // 「我的」与「某某的」清楚区分：我的标注行 + 组员方案区标题。
    // 曲线卡在本页页尾，滚回我的标注行再断言；行贴视口上缘时区标题在
    // 缓存外，往回拖一点让标题进入视口。
    await _scrollToKey(tester, 'scheme_open_mine');
    await tester.drag(find.byType(ListView).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('我的标注'), findsOneWidget);
    expect(find.text('组员方案'), findsOneWidget);
  });

  testWidgets('组员方案读取失败：行内错误条如实说明，不假装无方案', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(
      tester,
      videoId: 'v1',
      extraOverrides: [
        memberSchemesProvider.overrideWith(
          (ref, videoId) async => throw StateError('方案文件读不了'),
        ),
      ],
    );

    await _scrollToKey(tester, 'dance_scheme_error');
    expect(find.byKey(const Key('dance_scheme_error')), findsOneWidget);
    expect(find.text('组员方案读取失败'), findsOneWidget);
    // 失败不是「没有方案」：不出方案区标题与我的标注行。
    expect(find.text('组员方案'), findsNothing);
    expect(find.byKey(const Key('scheme_open_mine')), findsNothing);
  });

  testWidgets('逐条删除：确认弹窗默认不删；确认后只删那一条，我的标注文档原样', (tester) async {
    final memberStorage = await _schemesStorage([
      MemberSchemeRecord(
        schemeId: 's1',
        memberName: '小如',
        importedAt: DateTime(2026, 9, 10),
      ),
      MemberSchemeRecord(
        schemeId: 's2',
        memberName: '阿队',
        importedAt: DateTime(2026, 9, 11),
      ),
    ]);
    final documents = _documents(
      markers: const MarkersDocument(signature: SongSignature(song: '我的标注')),
      local: const LocalDocument(mastery: {0: LearningMastery.familiar}),
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': documents},
      memberStorage: memberStorage,
    );
    await harness.pump(tester, videoId: 'v1');

    // 确认弹窗默认不删：取消后两条都还在。
    await _scrollToKey(tester, 'dance_scheme_delete_s1');
    expect(await _schemesIn(memberStorage), ['s1', 's2']);
    await tester.tap(find.byKey(const Key('dance_scheme_delete_s1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheme_delete_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scheme_delete_cancel')));
    await tester.pumpAndSettle();
    expect(await _schemesIn(memberStorage), ['s1', 's2']);
    expect(find.byKey(const Key('dance_scheme_row_s1')), findsOneWidget);

    // 确认删除：只删 s1，s2 保留；我的两份文档原样。
    await tester.tap(find.byKey(const Key('dance_scheme_delete_s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scheme_delete_confirm')));
    await tester.pumpAndSettle();
    expect(await _schemesIn(memberStorage), ['s2']);
    expect(find.byKey(const Key('dance_scheme_row_s1')), findsNothing);
    expect(find.byKey(const Key('dance_scheme_row_s2')), findsOneWidget);
    expect(
      MarkersDocument.fromJson(documents.markersSnapshot).signature,
      const SongSignature(song: '我的标注'),
    );
    expect(LocalDocument.fromJson(documents.localSnapshot).mastery, const {
      0: LearningMastery.familiar,
    });
  });

  testWidgets('无组员方案：组员方案区不出现（空态不占视觉重量）', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester, videoId: 'v1');

    expect(find.text('组员方案'), findsNothing);
    expect(find.byKey(const Key('dance_scheme_row_s1')), findsNothing);
  });

  testWidgets('设备等效视口下组员方案行可达：滚动到即点得到，删除弹窗出现', (tester) async {
    // compact 档：组员方案区在逐段区之后，可能要滚动才可达——
    // 可达性 ≠ 存在性，按真手势断言。
    useNamedViewport(tester, ViewportTier.compact);

    final memberStorage = await _schemesStorage([
      MemberSchemeRecord(
        schemeId: 's1',
        memberName: '小如',
        importedAt: DateTime(2026, 9, 10),
      ),
      MemberSchemeRecord(
        schemeId: 's2',
        memberName: '阿队',
        importedAt: DateTime(2026, 9, 11),
      ),
    ]);
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeEndMs: 24000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
          ),
          local: const LocalDocument.empty(),
        ),
      },
      memberStorage: memberStorage,
    );
    await harness.pump(tester, videoId: 'v1');

    // 逐段区在前、组员方案区在后：滚到最后一行再按删除，真的按到 → 弹窗。
    await tester.scrollUntilVisible(
      find.byKey(const Key('dance_scheme_delete_s2')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_scheme_delete_s2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheme_delete_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scheme_delete_cancel')));
    await tester.pumpAndSettle();
    expect(await _schemesIn(memberStorage), ['s1', 's2']);
  });

  testWidgets('删除这支舞确认弹窗文案含组员方案', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester, videoId: 'v1');

    await _openMoreMenu(tester);
    await tester.tap(find.byKey(const Key('dance_detail_delete')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('dance_delete_dialog')),
        matching: find.textContaining('组员方案'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('⋯ 菜单出现「分享」；点开分享面，三项勾选默认值正确', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('detail_share_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': InMemoryVideoDocumentStorage(
          markers: MarkersDocument(
            rangeEndMs: 24000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
          ).toJson(),
        ),
      },
    );
    await harness._pump(
      tester,
      MaterialApp(home: DanceDetailPage(videoId: 'v1')),
      extraOverrides: [
        materialsBaseDirectoryProvider.overrideWithValue(() async => tempDir),
        materialManifestStoreProvider.overrideWith(
          (ref) => MaterialManifestStore(MemoryManifestStorage()),
        ),
        shareChannelProvider.overrideWithValue(FakeShareChannel()),
        susumeShareDirectoryProvider.overrideWith(
          (ref) async => Directory('${tempDir.path}/out'),
        ),
        outboundSchemeIdStoreProvider.overrideWithValue(
          OutboundSchemeIdFileStore(File('${tempDir.path}/scheme_ids.json')),
        ),
      ],
    );

    await _openMoreMenu(tester);
    expect(find.byKey(const Key('dance_detail_share')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dance_detail_share')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('share_sheet')), findsOneWidget);
    Checkbox valueOf(String key) => tester.widget<Checkbox>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Checkbox),
      ),
    );
    expect(valueOf('share_sheet_source_video').value, isTrue);
    expect(valueOf('share_sheet_mastery').value, isFalse);
    // 本支舞没有练习录像：不出现该勾选项。
    expect(find.textContaining('带练习录像'), findsNothing);
  });

  testWidgets('⋯ 菜单「分享视频（mp4）」：递出源视频副本原件，不生成包', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('detail_mp4_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final mp4 = File('${tempDir.path}/source.mp4');
    mp4.writeAsBytesSync(const [1, 2, 3]);

    final channel = FakeShareChannel();
    final harness = _Harness(
      index: VideoIndex(
        entries: [
          VideoIndexEntry(
            videoId: 'v1',
            displayName: 'source.mp4',
            filePath: mp4.path,
            sizeBytes: 3,
            fastKey: 'k-v1',
            mirrored: false,
            lastOpenedAt: DateTime(2026, 9, 1),
          ),
        ],
      ),
    );
    await harness._pump(
      tester,
      MaterialApp(home: DanceDetailPage(videoId: 'v1')),
      extraOverrides: [shareChannelProvider.overrideWithValue(channel)],
    );

    await _openMoreMenu(tester);
    final item = tester.widget<PopupMenuItem<String>>(
      find.byKey(const Key('dance_detail_share_mp4')),
    );
    expect(item.enabled, isTrue);
    expect(find.text('分享视频（mp4）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dance_detail_share_mp4')));
    await tester.pumpAndSettle();

    // 递出的就是源视频副本原件（mp4），不是 .susume 包。
    expect(channel.sharedFiles, hasLength(1));
    expect(channel.sharedFiles.single.path, mp4.path);
    expect(channel.sharedFiles.single.path, endsWith('.mp4'));
    expect(Directory('${tempDir.path}/out').existsSync(), isFalse);
  });

  testWidgets('源视频副本不在：「分享视频（mp4）」置灰并说明原因', (tester) async {
    final channel = FakeShareChannel();
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness._pump(
      tester,
      MaterialApp(home: DanceDetailPage(videoId: 'v1')),
      extraOverrides: [shareChannelProvider.overrideWithValue(channel)],
    );

    await _openMoreMenu(tester);
    final item = tester.widget<PopupMenuItem<String>>(
      find.byKey(const Key('dance_detail_share_mp4')),
    );
    expect(item.enabled, isFalse);
    expect(
      find.byKey(const Key('dance_detail_share_mp4_missing')),
      findsOneWidget,
    );
    // 置灰即点不动：不递出任何文件。
    await tester.tap(find.byKey(const Key('dance_detail_share_mp4')));
    await tester.pumpAndSettle();
    expect(channel.sharedFiles, isEmpty);
  });

  testWidgets('方案区是一排入口：我的标注与组员方案并列成行，页面上没有装载态指示', (tester) async {
    final memberStorage = await _schemesStorage([
      MemberSchemeRecord(
        schemeId: 's1',
        memberName: '小如',
        schemeName: '队长版',
        mastery: const {0: 4},
        importedAt: DateTime(2026, 9, 10),
      ),
    ]);
    // 我的公开文档为空（新导入、还没有内容）：不带参数打开也恒用我的方案
    // 两个入口都在页面上；至于「哪一份正装载」，页面上没有
    // 这个状态。
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      memberStorage: memberStorage,
    );
    await harness.pump(tester, videoId: 'v1');

    await _scrollToKey(tester, 'scheme_open_mine');
    expect(find.byKey(const Key('scheme_open_mine')), findsOneWidget);
    expect(find.byKey(const Key('dance_scheme_row_s1')), findsOneWidget);
    expect(find.text('装载中'), findsNothing);
  });

  testWidgets('点组员方案行：以那一份方案进播放（只读），退出后我的激活原样', (tester) async {
    final memberStorage = await _schemesStorage([
      MemberSchemeRecord(
        schemeId: 's1',
        memberName: '小如',
        importedAt: DateTime(2026, 9, 10),
      ),
    ]);
    final docs = InMemoryVideoDocumentStorage(
      markers: MarkersDocument(
        rangeEndMs: 120000,
        segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
      ).toJson(),
      local: const LocalDocument(activatedSegments: [1]).toJson(),
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': docs},
      memberStorage: memberStorage,
    );
    await harness._pump(
      tester,
      MaterialApp(home: DanceDetailPage(videoId: 'v1')),
      // 打开会话识别身份（真实打开恢复接线跑起来）才谈得上「退出后逐位相同」。
      extraOverrides: [
        contentHasherProvider.overrideWithValue(const FixedHasher('v1')),
      ],
    );

    await _scrollToKey(tester, 'dance_scheme_open_s1');
    await tester.tap(find.byKey(const Key('dance_scheme_open_s1')));
    await tester.pumpAndSettle();

    // 进的是播放器，带的是这一行的方案参数（组员方案 → 只读）。
    final page = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(page.scheme, isA<MemberSchemeOpen>());
    expect((page.scheme as MemberSchemeOpen).schemeId, 's1');
    expect(
      harness.engine.source!.toFilePath(),
      '/videos/v1.mp4',
      reason: '打开的是这条索引条目的视频副本',
    );

    // 退出回详情页（播放页无标准返回钮，走系统返回通道）：我的落盘激活与查看前逐位相同。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // 页尾新增曲线卡后列表更长：退出后向上滚回顶部主钮再断言。
    await tester.scrollUntilVisible(
      find.byKey(const Key('dance_detail_open')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_detail_open')), findsOneWidget);
    expect(
      (docs.localSnapshot['session']
          as Map<String, dynamic>)['activatedSegments'],
      <int>[1],
    );
  });

  testWidgets('点「我的标注」行：以我的方案进播放（可写）', (tester) async {
    final memberStorage = await _schemesStorage([
      MemberSchemeRecord(
        schemeId: 's1',
        memberName: '小如',
        importedAt: DateTime(2026, 9, 10),
      ),
    ]);
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      memberStorage: memberStorage,
    );
    await harness.pump(tester, videoId: 'v1');

    await _scrollToKey(tester, 'scheme_open_mine');
    await tester.tap(find.byKey(const Key('scheme_open_mine')));
    await tester.pumpAndSettle();

    final page = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(page.scheme, isA<MySchemeOpen>());
  });

  testWidgets('首页卡片派生量恒取我的方案，且卡片打开不带方案参数', (tester) async {
    final memberStorage = await _schemesStorage([
      MemberSchemeRecord(
        schemeId: 's1',
        memberName: '小如',
        mastery: const {0: 0, 1: 0, 2: 0, 3: 0},
        importedAt: DateTime(2026, 9, 10),
      ),
    ]);
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeEndMs: 240000,
            segmentLines: const [
              SegmentLine(position: Duration(seconds: 60)),
              SegmentLine(position: Duration(seconds: 120)),
              SegmentLine(position: Duration(seconds: 180)),
            ],
          ),
          local: const LocalDocument(
            mastery: {
              0: LearningMastery.mastered,
              1: LearningMastery.mastered,
              2: LearningMastery.mastered,
              3: LearningMastery.mastered,
            },
          ),
        ),
      },
      memberStorage: memberStorage,
    );
    await harness.pumpHome(tester);

    // 卡片显示我的熟练度（全段最高档 = 100%）与完成勾——组员方案那份全为
    // 未练（0%）不进卡片。
    expect(_inCard('v1', '100%'), findsOneWidget);
    expect(
      find.byKey(const Key('dance_card_badge_mastered_v1')),
      findsOneWidget,
    );

    // 点卡片主体：不带方案参数打开，恒用我的方案（无例外）。
    await tester.tap(find.byKey(const Key('dance_card_v1')));
    await tester.pumpAndSettle();
    final page = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(page.scheme, isA<AutoSchemeOpen>());
  });

  testWidgets('练习分布曲线：默认时长/累计，时间标签就位、四拍序号不出现', (tester) async {
    final harness = _distributionHarness();
    await harness.pump(tester, videoId: 'v1');

    await _scrollToKey(tester, 'practice_distribution_card');
    expect(find.byKey(const Key('practice_distribution_card')), findsOneWidget);
    // 「按分段 / 按八拍」整行退场。
    expect(find.byKey(const Key('practice_axis_segment')), findsNothing);
    expect(find.byKey(const Key('practice_axis_eightBeat')), findsNothing);
    expect(_chipSelected(tester, 'practice_metric_duration'), isTrue);
    expect(_chipSelected(tester, 'practice_metric_count'), isFalse);
    expect(_chipSelected(tester, 'practice_range_cumulative'), isTrue);
    expect(_chipSelected(tester, 'practice_range_last7Days'), isFalse);
    expect(_chipSelected(tester, 'practice_range_today'), isFalse);

    // 横轴是歌曲时间：网格 ⇒ 13 个四拍桶，取 4 档标签（1/9/17/25s）。
    // 标签行在视口下方惰性构建：先按步进拖到它出现。
    final labels = find.byKey(const Key('practice_time_label_12'));
    for (var i = 0; i < 30 && labels.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();
    }
    expect(labels, findsOneWidget);
    expect(find.text('0:01'), findsOneWidget);
    expect(find.text('0:09'), findsOneWidget);
    expect(find.text('0:17'), findsOneWidget);
    expect(find.text('0:25'), findsOneWidget);
    // 四拍序号与逐点读数在图内不出现（页面上段行的「八拍区间」读数仍照旧
    // 显示）。
    final card = find.byKey(const Key('practice_distribution_card'));
    expect(
      find.descendant(of: card, matching: find.textContaining('八拍')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('第 ')),
      findsNothing,
    );
    expect(find.byKey(const Key('practice_point_0')), findsNothing);
    expect(find.byKey(const Key('practice_dot_0')), findsNothing);
    expect(
      find.byKey(const Key('practice_distribution_selected')),
      findsNothing,
    );
  });

  testWidgets('练习分布曲线：切次数口径曲线重画，序号仍不出现', (tester) async {
    final harness = _distributionHarness();
    await harness.pump(tester, videoId: 'v1');

    await _scrollToKey(tester, 'practice_metric_count');
    await tester.tap(find.byKey(const Key('practice_metric_count')));
    await tester.pumpAndSettle();
    expect(_chipSelected(tester, 'practice_metric_count'), isTrue);

    await _scrollToKey(tester, 'practice_distribution_chart');
    expect(
      find.byKey(const Key('practice_distribution_chart')),
      findsOneWidget,
    );
    expect(find.text('0:01'), findsOneWidget);
    expect(find.textContaining('八拍'), findsNothing);
    expect(find.textContaining('第 '), findsNothing);
  });

  testWidgets('练习分布曲线：切范围按筛选后的桶重算', (tester) async {
    final todayKey = localDayKey(DateTime.now());
    final oldKey = localDayKey(
      DateTime.now().subtract(const Duration(days: 10)),
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeEndMs: 8000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 3))],
            beat: uniformDownbeatGridDoc(seconds: 8),
          ),
          local: const LocalDocument.empty(),
        ),
      },
      bucketStorage: _bucketsOn({
        oldKey: _keyed({
          0: const FourBeatBucketValue(wallSeconds: 8, sweeps: 9),
          1: const FourBeatBucketValue(wallSeconds: 2, sweeps: 9),
        }),
        todayKey: _keyed({
          0: const FourBeatBucketValue(wallSeconds: 1, sweeps: 2),
          1: const FourBeatBucketValue(wallSeconds: 1, sweeps: 4),
        }),
      }),
    );
    await harness.pump(tester, videoId: 'v1');

    // 累计：桶 0 收全期两笔（8s + 1s）。
    await _scrollToKey(tester, 'practice_distribution_card');
    expect(_distributionBucketDuration(tester, 0), const Duration(seconds: 9));

    await _scrollToKey(tester, 'practice_range_today');
    await tester.tap(find.byKey(const Key('practice_range_today')));
    await tester.pumpAndSettle();
    // 今日：曲线随范围重算，桶 0 只取今日那笔。
    expect(_distributionBucketDuration(tester, 0), const Duration(seconds: 1));

    // 近 7 天：10 天前那笔落在窗口外 ⇒ 与今日同值。
    await _scrollToKey(tester, 'practice_range_last7Days');
    await tester.tap(find.byKey(const Key('practice_range_last7Days')));
    await tester.pumpAndSettle();
    expect(_distributionBucketDuration(tester, 0), const Duration(seconds: 1));

    // 切回累计：回到两笔之和。
    await _scrollToKey(tester, 'practice_range_cumulative');
    await tester.tap(find.byKey(const Key('practice_range_cumulative')));
    await tester.pumpAndSettle();
    expect(_distributionBucketDuration(tester, 0), const Duration(seconds: 9));
  });

  testWidgets('段级气泡读数跟随范围口径：换范围后气泡数值跟着变', (tester) async {
    final todayKey = localDayKey(DateTime.now());
    final oldKey = localDayKey(
      DateTime.now().subtract(const Duration(days: 10)),
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeEndMs: 8000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 3))],
            beat: uniformDownbeatGridDoc(seconds: 8),
          ),
          local: const LocalDocument.empty(),
        ),
      },
      bucketStorage: _bucketsOn({
        oldKey: _keyed({
          0: const FourBeatBucketValue(wallSeconds: 8, sweeps: 9),
          1: const FourBeatBucketValue(wallSeconds: 2, sweeps: 9),
        }),
        todayKey: _keyed({
          0: const FourBeatBucketValue(wallSeconds: 1, sweeps: 2),
          1: const FourBeatBucketValue(wallSeconds: 1, sweeps: 4),
        }),
      }),
    );
    await harness.pump(tester, videoId: 'v1');
    await _scrollToKey(tester, 'practice_gridlines');

    // 点在第 1 段内（时刻 2.5s，绘图区局部坐标按真实时间轴换算）。
    final plot = tester.getRect(find.byKey(const Key('practice_gridlines')));
    const pad = 18.0;
    final x = pad + (plot.width - pad * 2) * (2.5 - 2) / 4;
    await tester.tapAt(plot.topLeft + Offset(x, 70));
    await tester.pumpAndSettle();

    // 累计口径：段 1 = 桶 0 全期两笔（8s + 1s），遍数 9 + 2 = 11。
    expect(find.text('第 1 段 · 0:00–0:03'), findsOneWidget);
    // 累计口径：段 1 = 左界落在 [0,3s) 的桶（全期两笔：9s + 3s），
    // 遍数 = 段内桶扫过次数的最小值 11。
    expect(find.text('练习 0:12 · 11 遍'), findsOneWidget);

    // 切今日：气泡读数就地跟随（气泡保持打开）。
    await _scrollToKey(tester, 'practice_range_today');
    await tester.tap(find.byKey(const Key('practice_range_today')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('practice_segment_bubble')), findsOneWidget);
    expect(find.text('练习 0:02 · 2 遍'), findsOneWidget);
    expect(find.text('练习 0:12 · 11 遍'), findsNothing);
  });

  testWidgets('练习分布曲线：网格未就绪时显示既有空态文案', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: const MarkersDocument(
            rangeEndMs: 24000,
            segmentLines: [SegmentLine(position: Duration(seconds: 8))],
          ),
          local: const LocalDocument.empty(),
        ),
      },
      bucketStorage: _buckets({
        0: const FourBeatBucketValue(wallSeconds: 10, sweeps: 3),
      }),
    );
    await harness.pump(tester, videoId: 'v1');

    await _scrollToKey(tester, 'practice_distribution_empty');
    expect(_distributionEmpty('该时段无节拍数据'), findsOneWidget);
    expect(find.byKey(const Key('practice_distribution_chart')), findsNothing);
  });

  // ---- 封面横幅----

  testWidgets('详情顶部封面横幅：就绪时固定高度横条中心裁切渲染该舞封面图', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      coverCache: InMemoryCoverCache(
        ready: const {'v1'},
        positions: const {'v1': Duration.zero},
      ),
    );
    await harness.pump(tester, videoId: 'v1');

    final banner = find.byKey(const Key('dance_detail_cover_banner'));
    expect(banner, findsOneWidget);
    // 固定高度横条：高 200，不随封面图片自身的 3:4 / 4:3 比例变。
    final bannerRect = tester.getRect(banner);
    expect(bannerRect.height, 200);
    expect(bannerRect.width, greaterThan(bannerRect.height));

    final image = tester.widget<Image>(
      find.byKey(const Key('dance_detail_cover_image')),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, Alignment.center);
    expect(find.byKey(const Key('dance_detail_cover_image')), findsOneWidget);
    expect(
      find.byKey(const Key('dance_detail_cover_placeholder')),
      findsNothing,
    );
  });

  testWidgets('详情顶部封面横幅：封面未就绪显示占位图，详情其余区块照常', (tester) async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    await harness.pump(tester, videoId: 'v1');

    expect(find.byKey(const Key('dance_detail_cover_banner')), findsOneWidget);
    expect(
      find.byKey(const Key('dance_detail_cover_placeholder')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('dance_detail_cover_image')), findsNothing);
    expect(_value('dance_detail_total', '0:00'), findsOneWidget);
    expect(find.byKey(const Key('dance_detail_open')), findsOneWidget);
  });

  // ---- 换封面入口----

  testWidgets('⋯ 菜单「换封面」与其他管理动作同排：点入简化选帧界面，返回零写入', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: const MarkersDocument.empty(),
          local: const LocalDocument.empty(),
        ),
      },
    );
    await harness.pump(tester, videoId: 'v1');

    await _openMoreMenu(tester);
    // 与其它管理动作同排：改名/删除所在的那一份菜单里。
    expect(find.byKey(const Key('dance_detail_change_cover')), findsOneWidget);
    expect(find.byKey(const Key('dance_detail_rename')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dance_detail_change_cover')));
    await tester.pumpAndSettle();

    // 简化选帧界面：时间轴 + 预览线 + 当前时刻 + 两个动作。
    expect(find.byKey(const Key('cover_picker_page')), findsOneWidget);
    expect(find.byKey(const Key('cover_picker_timeline')), findsOneWidget);
    expect(find.byKey(const Key('cover_picker_time')), findsOneWidget);
    expect(find.text('用这一帧'), findsOneWidget);
    expect(find.text('恢复为默认'), findsOneWidget);
    // 复用同一内核：打开该舞源视频并暂停。
    expect(harness.engine.source, Uri.file('/videos/v1.mp4'));
    expect(harness.engine.isPlaying, isFalse);

    // 返回：不写入任何字段，内核不被释放。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cover_picker_page')), findsNothing);
    expect(
      harness.documents['v1']!.markersSnapshot['meta'] ?? const {},
      isNot(contains('coverPositionMs')),
    );
    expect(harness.engine.isDisposed, isFalse);
  });

  testWidgets('「用这一帧」确认：写入位置并重新生成后，详情立即显示新封面', (tester) async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: const MarkersDocument.empty(),
          local: const LocalDocument.empty(),
        ),
      },
    );
    await harness.pump(tester, videoId: 'v1');
    // 进入时封面未就绪：占位图。
    expect(
      find.byKey(const Key('dance_detail_cover_placeholder')),
      findsOneWidget,
    );

    await _openMoreMenu(tester);
    await tester.tap(find.byKey(const Key('dance_detail_change_cover')));
    await tester.pumpAndSettle();

    // 拖动预览线 150px：默认视口时间轴宽 768 → 3 分钟全长对应 35156ms。
    await tester.drag(
      find.byKey(const Key('cover_picker_timeline')),
      const Offset(150, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cover_picker_confirm')));
    await tester.pumpAndSettle();

    // 回到详情：字段落盘为预览线时刻，缓存按该时刻重新生成并立即出真图。
    expect(find.byKey(const Key('cover_picker_page')), findsNothing);
    expect(
      MarkersDocument.fromJson(harness.documents['v1']!.markersSnapshot)
          .coverPositionMs,
      35156,
    );
    expect(
      harness.coverGenerator.calls.single.position,
      const Duration(milliseconds: 35156),
    );
    expect(find.byKey(const Key('dance_detail_cover_image')), findsOneWidget);
    expect(
      find.byKey(const Key('dance_detail_cover_placeholder')),
      findsNothing,
    );
  });

  testWidgets('封面横幅不把总览与「继续播放」挤出首屏', (tester) async {
    useNamedViewport(tester, ViewportTier.compact);
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      coverCache: InMemoryCoverCache(
        ready: const {'v1'},
        positions: const {'v1': Duration.zero},
      ),
    );
    await harness.pump(tester, videoId: 'v1');

    // compact 档（361.1×781.7dp）下横幅仍是横条而非占屏主体：
    // 横幅高固定 200（视口无关），内容宽约 337 → 宽高比约 1.69。
    final bannerRect = tester.getRect(
      find.byKey(const Key('dance_detail_cover_banner')),
    );
    expect(bannerRect.width / bannerRect.height, greaterThan(1.5));

    final firstScreenBottom = tester.getRect(find.byType(ListView)).bottom;
    for (final key in const [
      'dance_detail_cover_banner',
      'dance_detail_total',
      'dance_detail_last',
      'dance_detail_average',
      'dance_detail_mastered',
      'dance_detail_open',
    ]) {
      expect(
        tester.getRect(find.byKey(Key(key))).bottom,
        lessThanOrEqualTo(firstScreenBottom),
        reason: key,
      );
    }
  });
}

/// 滚动到目标行：先向下找，找不到再向上找（回到视口上方的行）；找到后
/// 再 ensureVisible，保证目标真的在视口内可点。
Future<void> _scrollToKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    final list = find.byType(Scrollable).first;
    var down = 0;
    while (finder.evaluate().isEmpty && down < 30) {
      down++;
      await tester.drag(list, const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    var up = 0;
    while (finder.evaluate().isEmpty && up < 30) {
      up++;
      await tester.drag(list, const Offset(0, 200));
      await tester.pumpAndSettle();
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Finder _inCard(String videoId, String text) => find.descendant(
  of: find.byKey(Key('dance_card_$videoId')),
  matching: find.text(text),
);

/// 展开右上「⋯」菜单（改名/删除的入口）。
Future<void> _openMoreMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('dance_detail_more')));
  await tester.pumpAndSettle();
}

/// 收起右上「⋯」菜单（点菜单外空白处）。
Future<void> _dismissMoreMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 500));
  await tester.pumpAndSettle();
}

/// 总览某项的值文本。
Finder _value(String key, String text) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

/// 练习分布卡片某个切换档是否选中。
bool _chipSelected(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

/// 「页面→卡片」接缝断言：读 [PracticeDistributionCard] 的构造入参（该卡片
/// 在页面读面上没有其它出口），验页面按当前范围筛出的桶数据。
/// 练习分布卡片当前收到的某个四拍桶的时长。
Duration _distributionBucketDuration(WidgetTester tester, int index) => tester
    .widget<PracticeDistributionCard>(find.byType(PracticeDistributionCard))
    .buckets[index]
    .duration;

/// 练习分布卡片空态文案（网格未就绪）。
Finder _distributionEmpty(String text) => find.descendant(
  of: find.byKey(const Key('practice_distribution_empty')),
  matching: find.text(text),
);

/// 曲线用例共用装配：两段（分段线 8s）、24s 就绪均匀网格、桶 0–11 有值。
_Harness _distributionHarness() => _Harness(
  index: VideoIndex(entries: [_entry('v1')]),
  documents: {
    'v1': _documents(
      markers: MarkersDocument(
        rangeEndMs: 24000,
        segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
        beat: uniformDownbeatGridDoc(seconds: 24),
      ),
      local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
    ),
  },
  bucketStorage: _buckets({
    // 四拍桶左边界 = 2s × 桶序号；分段线在 8s。
    0: const FourBeatBucketValue(wallSeconds: 10, sweeps: 3),
    1: const FourBeatBucketValue(wallSeconds: 20, sweeps: 2),
    2: const FourBeatBucketValue(wallSeconds: 1, sweeps: 5),
    3: const FourBeatBucketValue(wallSeconds: 1, sweeps: 1),
    4: const FourBeatBucketValue(wallSeconds: 5, sweeps: 4),
    for (var i = 5; i <= 11; i++)
      i: const FourBeatBucketValue(wallSeconds: 1, sweeps: 6),
  }),
);

/// 某张卡片内的文本。
Finder _cardText(String videoId, String text) => find.descendant(
  of: find.byKey(Key('dance_card_$videoId')),
  matching: find.text(text),
);

/// 组员方案行内某项的文本。
Finder _schemeText(String key, String text) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

/// 预置组员方案的内存存取（upsert 走同一条写链，落盘形状与生产一致）。
Future<InMemoryMemberSchemeStorage> _schemesStorage(
  List<MemberSchemeRecord> records,
) async {
  final storage = InMemoryMemberSchemeStorage();
  final store = MemberSchemeStore(storage);
  for (final record in records) {
    await store.upsert(record);
  }
  return storage;
}

/// 当前落盘的方案标识（按落盘次序）。
Future<List<String>> _schemesIn(InMemoryMemberSchemeStorage storage) async =>
    (await MemberSchemeStore(
      storage,
    ).read()).schemes.map((scheme) => scheme.schemeId).toList();

class _Harness {
  _Harness({
    required VideoIndex index,
    this.documents = const {},
    List<PracticeSessionRecord> records = const [],
    this.storageFactory,
    InMemoryMemberSchemeStorage? memberStorage,
    InMemoryFourBeatBucketStorage? bucketStorage,
    InMemoryCoverCache? coverCache,
  }) : indexStorage = InMemoryVideoIndexStorage(initial: index),
       statsStorage = InMemoryPracticeStatsStorage(),
       memberStorage = memberStorage ?? InMemoryMemberSchemeStorage(),
       bucketStorage = bucketStorage ?? InMemoryFourBeatBucketStorage(),
       coverCache = coverCache ?? InMemoryCoverCache(),
       engine = FakePlaybackEngine() {
    if (records.isNotEmpty) {
      statsStorage.rawJson = PracticeStatsDocument(sessions: records).toJson();
    }
    statsStore = PracticeStatsStore(statsStorage);
  }

  final InMemoryVideoIndexStorage indexStorage;
  final InMemoryPracticeStatsStorage statsStorage;
  final Map<String, InMemoryVideoDocumentStorage> documents;
  final InMemoryMemberSchemeStorage memberStorage;
  final InMemoryFourBeatBucketStorage bucketStorage;

  /// 封面缓存替身：`ready` 集合即封面是否就绪，决定横幅出真图还是占位图。
  final InMemoryCoverCache coverCache;
  final FakePlaybackEngine engine;

  /// 封面生成替身：分享「用这一帧」按预览线时刻调用的断言与缓存侧收口。
  late final FakeCoverGenerator coverGenerator = FakeCoverGenerator(
    cache: coverCache,
  );

  /// 按 videoId 取存储；缺省取 [documents]、再缺省空实例。写失败用例用它
  /// 替换成会抛错的替身。
  final VideoDocumentStorage Function(String videoId)? storageFactory;

  late final PracticeStatsStore statsStore;

  Future<void> pump(
    WidgetTester tester, {
    required String videoId,
    List<dynamic> extraOverrides = const [],
  }) => _pump(
    tester,
    MaterialApp(home: DanceDetailPage(videoId: videoId)),
    extraOverrides: extraOverrides,
  );

  /// 从首页进详情（卡片标题与详情同显新名的闭环用）。
  Future<void> pumpHome(WidgetTester tester) {
    useNamedViewport(tester, ViewportTier.compact);
    return _pump(tester, const DanceLearningApp());
  }

  Future<void> _pump(
    WidgetTester tester,
    Widget home, {
    List<dynamic> extraOverrides = const [],
  }) async {
    final factory = storageFactory;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoIndexStoreProvider.overrideWithValue(indexStorage),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            factory ?? (id) => documents[id] ?? InMemoryVideoDocumentStorage(),
          ),
          coverCacheProvider.overrideWith((ref) => coverCache),
          coverGeneratorProvider.overrideWith((ref) async => coverGenerator),
          practicePlanStorageProvider.overrideWithValue(
            InMemoryPracticePlanStorage(),
          ),
          practiceStatsStoreProvider.overrideWithValue(statsStore),
          fourBeatBucketStoreProvider.overrideWithValue(
            FourBeatBucketStore(bucketStorage),
          ),
          memberSchemeStoreProvider.overrideWith(
            (ref, videoId) => MemberSchemeStore(memberStorage),
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
          ...extraOverrides,
        ],
        child: home,
      ),
    );
    await tester.pumpAndSettle();
  }
}

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);

InMemoryVideoDocumentStorage _documents({
  required MarkersDocument markers,
  required LocalDocument local,
}) => InMemoryVideoDocumentStorage(
  markers: markers.toJson(),
  local: local.toJson(),
);

Map<FourBeatBucketKey, FourBeatBucketValue> _keyed(
  Map<int, FourBeatBucketValue> buckets,
) => {
  for (final entry in buckets.entries)
    FourBeatBucketKey(1, entry.key): entry.value,
};

/// 预置某舞的四拍桶分片（单本地日、桶序号 → 值），落在内存存取上。
InMemoryFourBeatBucketStorage _buckets(
  Map<int, FourBeatBucketValue> buckets, {
  String videoId = 'v1',
  String day = '2026-09-15',
}) => _bucketsOn({day: _keyed(buckets)}, videoId: videoId);

/// 预置某舞的四拍桶分片（多本地日、桶键 → 值），落在内存存取上。
InMemoryFourBeatBucketStorage _bucketsOn(
  Map<String, Map<FourBeatBucketKey, FourBeatBucketValue>> days, {
  String videoId = 'v1',
}) {
  final storage = InMemoryFourBeatBucketStorage();
  storage.setRaw(
    videoId,
    FourBeatBucketShard(
      days: {
        for (final entry in days.entries)
          entry.key: FourBeatBucketDay(buckets: entry.value),
      },
    ).toJson(),
  );
  return storage;
}
