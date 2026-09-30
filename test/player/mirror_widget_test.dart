import 'dart:io';

import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationEditorProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/note_sticker_layout.dart'
    show noteStickerRect;
import 'package:dance_learning_app/player/note_sticker_overlay.dart'
    show NoteStickerText;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show screenBrightnessControllerProvider;
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import '../helpers/video_surface.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/device_viewport.dart';

void main() {
  late Directory tempDir;
  late File sourceFile;

  setUp(() {
    // 夹具文件操作用同步 IO（widget 测试的 fake async 时钟下真实异步
    // IO 不可完成，见 import_flow_test 注释）。
    tempDir = Directory.systemTemp.createTempSync('mirror_widget_test');
    sourceFile = File(p.join(tempDir.path, 'dance.mp4'))
      ..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// 未询问过的条目（模拟后台哈希先落盘的首次导入；videoId 固定便于断言）。
  VideoIndexEntry unaskedEntry(String filePath, {bool mirrored = false}) {
    return VideoIndexEntry(
      videoId: 'hash-1',
      displayName: 'dance.mp4',
      filePath: filePath,
      sizeBytes: 3,
      fastKey: fastKeyFor(name: 'dance.mp4', sizeBytes: 3),
      mirrored: mirrored,
      mirrorAsked: false,
      lastOpenedAt: DateTime(2026, 9, 1, 12),
    );
  }

  Future<void> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    required InMemoryVideoIndexStorage storage,
    Map<String, dynamic> markers = const {},
    ContentHasher? hasher,
  }) async {
    // 打开会话与镜像控制器共读同一份内存文档与同一身份：缺省固定哈希取
    // 种子条目 videoId（'seeded'），摘要相符 → 身份取条目；种子条目为
    // 其它 videoId（如 'hash-1'）时按新视频（entry 为 null）。
    final docStorage = InMemoryVideoDocumentStorage(markers: markers);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          screenBrightnessControllerProvider.overrideWithValue(
            FakeScreenBrightnessController(),
          ),
          videoIndexStoreProvider.overrideWithValue(storage),
          contentHasherProvider.overrideWithValue(
            hasher ?? const FixedHasher('hash-1'),
          ),
          // 打开会话读两份文档（工厂）与镜像控制器读 markers（协调器）指向
          // 同一份内存文档：真实实现走 path_provider + 文件哈希，在
          // flutter_test 的 fake async 时钟下不完成。
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => docStorage,
          ),
          videoDocumentCoordinatorProvider.overrideWith(
            (ref, videoId) => VideoDocumentCoordinator(docStorage),
          ),
        ],
        child: MaterialApp(home: PlayerPage(source: sourceFile.uri)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('首次打开：询问镜像', () {
    testWidgets('无历史：弹「需要镜像吗？」，选「右栏」立即翻转并持久化，源文件字节不变', (tester) async {
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage();
      await pumpPlayer(tester, engine: engine, storage: storage);

      // 询问卡片：标题 + 左右两栏依据大按钮；镜像未开启（无翻转）。
      expect(find.text('需要镜像吗？'), findsOneWidget);
      expect(find.byKey(const Key('mirror_yes_button')), findsOneWidget);
      expect(find.byKey(const Key('mirror_no_button')), findsOneWidget);
      expect(find.byKey(const Key('mirrored_surface')), findsNothing);

      // 后台哈希随后落盘（模拟首次导入：索引条目出现，初始镜像 false）。
      await storage.update(
        (index) => index.upsert(unaskedEntry(sourceFile.path)),
      );
      await tester.pump();

      // 选「是」：立即生效——画面水平翻转（渲染层）。
      await tester.tap(find.byKey(const Key('mirror_yes_button')));
      await tester.pump();
      expect(find.byKey(const Key('mirrored_surface')), findsOneWidget);
      expect(find.text('需要镜像吗？'), findsNothing);

      // 镜像状态按 video_id 持久化。
      expect(storage.current.entries.single.videoId, 'hash-1');
      expect(storage.current.entries.single.mirrored, isTrue);

      // 源视频文件字节不变（镜像为渲染层翻转，不写源文件）。
      expect(sourceFile.readAsBytesSync(), [1, 2, 3]);
    });

    testWidgets('选「否」：不翻转、按 video_id 持久化 false', (tester) async {
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage();
      await pumpPlayer(tester, engine: engine, storage: storage);
      expect(find.text('需要镜像吗？'), findsOneWidget);

      await storage.update(
        (index) => index.upsert(unaskedEntry(sourceFile.path, mirrored: true)),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('mirror_no_button')));
      await tester.pump();

      expect(find.byKey(const Key('mirrored_surface')), findsNothing);
      expect(find.text('需要镜像吗？'), findsNothing);
      expect(storage.current.entries.single.mirrored, isFalse);
      expect(sourceFile.readAsBytesSync(), [1, 2, 3]);
    });
    testWidgets('哈希先落盘但未询问过（竞态回归）：仍弹询问，不会被漏问', (tester) async {
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [unaskedEntry(sourceFile.path)]),
      );
      await pumpPlayer(tester, engine: engine, storage: storage);

      expect(
        find.text('需要镜像吗？'),
        findsOneWidget,
        reason: '条目未标记「已询问」→ 仍按首次打开询问',
      );
      expect(find.byKey(const Key('mirrored_surface')), findsNothing);

      await tester.tap(find.byKey(const Key('mirror_yes_button')));
      await tester.pump();
      expect(storage.current.entries.single.mirrored, isTrue);
      expect(storage.current.entries.single.mirrorAsked, isTrue);
    });
  });

  group('询问卡两栏依据（文案 / 次序 / 适配）', () {
    /// 真机竖屏基准视口：361.1 × 781.7dp（1264×2736 @3.5，唯一竖屏基准）。
    void setPortrait(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact);
    }

    /// 真机横屏：781.7 × 361.1dp（2736×1264 @3.5）。
    void setLandscape(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
    }

    // 文案逐字比对（含中文弯引号），不从实现复算。
    const subtitle = '对于正面拍摄的视频，总共需要一次镜像处理，就能像照镜子一样直接学';
    const noItems = [
      '视频来源已经镜像过了',
      '标题有“镜像”“镜面”的字样',
      '大多数舞蹈教程视频',
      '从背面拍摄的练习视频',
    ];
    const yesItems = ['没有镜像处理过的原始视频', '正片、舞台、练习室、比赛等作品'];

    final title = find.text('需要镜像吗？');
    final noTitle = find.text('不需要镜像');
    final yesTitle = find.text('需要镜像');
    final noColumn = find.byKey(const Key('mirror_no_button'));
    final yesColumn = find.byKey(const Key('mirror_yes_button'));

    /// 询问气泡的可视区（卡片内容盒）：内容超出时在它内部滚动。
    final viewport = find.descendant(
      of: find.byKey(const Key('mirror_question_scrim')),
      matching: find.byType(SingleChildScrollView),
    );

    /// 断言 [finder] 的绘制矩形完整落在气泡可视区内——不只「树里有这段
    /// 文本」，而是没被裁切/滚出可视区。
    void expectFullyInsideBubble(
      WidgetTester tester,
      Finder finder,
      String label,
    ) {
      final bubble = tester.getRect(viewport);
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(bubble.left - 0.5), reason: '$label：左缘未被裁');
      expect(rect.right, lessThanOrEqualTo(bubble.right + 0.5), reason: '$label：右缘未被裁');
      expect(rect.top, greaterThanOrEqualTo(bubble.top - 0.5), reason: '$label：上缘未被裁');
      expect(rect.bottom, lessThanOrEqualTo(bubble.bottom + 0.5), reason: '$label：下缘未被裁');
    }

    testWidgets('标题 + 副标题 + 两栏标题与全部条目逐字可见', (tester) async {
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage();
      await pumpPlayer(tester, engine: engine, storage: storage);

      expect(title, findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);
      expect(noTitle, findsOneWidget);
      expect(yesTitle, findsOneWidget);
      // 不只「树里有这段文本」，还要完整落在气泡可视区内（未被裁切）。
      expectFullyInsideBubble(tester, title, '标题');
      expectFullyInsideBubble(tester, find.text(subtitle), '副标题');
      expectFullyInsideBubble(tester, noTitle, '左栏标题');
      expectFullyInsideBubble(tester, yesTitle, '右栏标题');
      for (final item in noItems) {
        expect(find.text(item), findsOneWidget, reason: '左栏条目逐字可见：$item');
        expectFullyInsideBubble(tester, find.text(item), '左栏条目：$item');
      }
      for (final item in yesItems) {
        expect(find.text(item), findsOneWidget, reason: '右栏条目逐字可见：$item');
        expectFullyInsideBubble(tester, find.text(item), '右栏条目：$item');
      }
    });

    testWidgets('每条依据独立成行；「·」占固定列宽，文本折行仍与首行文字左缘对齐', (tester) async {
      setPortrait(tester);
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage();
      await pumpPlayer(tester, engine: engine, storage: storage);

      // 真机竖屏 361.1dp 下左栏正文约 115dp：第一条与第二条折成两行。
      final dots = find.descendant(of: noColumn, matching: find.text('·'));
      expect(dots, findsNWidgets(noItems.length));
      final dotLeft = tester.getRect(dots.at(0)).left;
      double? itemLeft;
      double? previousTop;
      for (var i = 0; i < noItems.length; i++) {
        final dotRect = tester.getRect(dots.at(i));
        expect(
          dotRect.left,
          moreOrLessEquals(dotLeft, epsilon: 0.5),
          reason: '「·」占固定列宽：各条点列左缘一致',
        );
        final itemRect = tester.getRect(
          find.descendant(of: noColumn, matching: find.text(noItems[i])),
        );
        itemLeft ??= itemRect.left;
        expect(
          itemRect.left,
          moreOrLessEquals(itemLeft, epsilon: 0.5),
          reason: '文本列固定：折行后与首行文字左缘对齐，不缩到点下面',
        );
        if (previousTop != null) {
          expect(itemRect.top, greaterThan(previousTop), reason: '每条依据独立成行');
        }
        previousTop = itemRect.top;
      }
      // 点与文字间距固定：文字列左缘 = 点列左缘 + 点列宽 + 间距。
      expect(
        itemLeft! - dotLeft,
        moreOrLessEquals(kNoticeCardDotWidth + kNoticeCardDotGap, epsilon: 0.5),
      );
      // 长条目确实折行（高度超过一行），折行后仍与首行文字左缘同列。
      expect(
        tester.getSize(
          find.descendant(of: noColumn, matching: find.text(noItems[1])),
        ).height,
        greaterThan(kNoticeCardItemSize * kNoticeCardItemLineHeight * 1.5),
        reason: '竖屏下长条目折行',
      );
    });

    testWidgets('左右次序：不需要镜像在左、需要镜像在右；两栏等宽等高、整栏可点有水波', (tester) async {
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage();
      await pumpPlayer(tester, engine: engine, storage: storage);

      final left = tester.getRect(noColumn);
      final right = tester.getRect(yesColumn);
      expect(left.left, lessThan(right.left), reason: '左栏=不需要镜像、右栏=需要镜像');
      expect(left.right, lessThanOrEqualTo(right.left), reason: '两栏不重叠');
      expect(
        tester.getTopLeft(noTitle).dx,
        lessThan(tester.getTopLeft(yesTitle).dx),
        reason: '两栏标题次序与栏位一致',
      );
      expect(left.width, moreOrLessEquals(right.width, epsilon: 0.5));
      expect(left.height, moreOrLessEquals(right.height, epsilon: 0.5));

      // 整栏是可点面：两栏都是接了作答的 InkWell（水波反馈的载体）。
      for (final column in [noColumn, yesColumn]) {
        expect(tester.widget<InkWell>(column).onTap, isNotNull, reason: '整栏可点');
      }
      // 后台哈希落盘（作答可持久化），随后按住左栏：越过 kPressTimeout 即起
      // 水波反馈动画（松手前有反馈）。
      await storage.update(
        (index) => index.upsert(unaskedEntry(sourceFile.path)),
      );
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(noColumn));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.hasRunningAnimations, isTrue, reason: '按下有水波反馈');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('点遮罩不关闭：模态必须作答', (tester) async {
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage();
      await pumpPlayer(tester, engine: engine, storage: storage);

      // 点气泡外的遮罩空白处（卡片居中，取屏幕左下角远离卡片）。
      await tester.tapAt(const Offset(8, 592));
      await tester.pump();

      expect(title, findsOneWidget, reason: '点遮罩不关闭，必须作答');
      expect(find.byKey(const Key('mirror_question_scrim')), findsOneWidget);
    });

    testWidgets('竖屏 361.1×781.7 与横屏 781.7×361.1：气泡在屏内居中、留边、无溢出', (tester) async {
      for (final (label, setViewport, width, height) in [
        ('竖屏', setPortrait, 1264 / 3.5, 2736 / 3.5),
        ('横屏', setLandscape, 2736 / 3.5, 1264 / 3.5),
      ]) {
        final engine = FakePlaybackEngine();
        final storage = InMemoryVideoIndexStorage();
        setViewport(tester);
        await pumpPlayer(tester, engine: engine, storage: storage);

        expect(title, findsOneWidget, reason: '$label：询问卡在屏');
        final bubble = tester.getRect(viewport);
        // 屏内 + 留边（最大高 = 屏高 − 上下留边；最大宽 = 屏宽 − 左右留边）。
        expect(bubble.left, greaterThanOrEqualTo(kNoticeCardScreenInsetH - 0.5), reason: '$label：左留边');
        expect(bubble.right, lessThanOrEqualTo(width - kNoticeCardScreenInsetH + 0.5), reason: '$label：右留边');
        expect(bubble.top, greaterThanOrEqualTo(kNoticeCardScreenInsetV - 0.5), reason: '$label：上留边');
        expect(bubble.bottom, lessThanOrEqualTo(height - kNoticeCardScreenInsetV + 0.5), reason: '$label：下留边');
        // 屏内居中（内容未顶到最大高时）。
        expect(bubble.center.dx, moreOrLessEquals(width / 2, epsilon: 0.5), reason: '$label：水平居中');
        expect(bubble.center.dy, moreOrLessEquals(height / 2, epsilon: 0.5), reason: '$label：垂直居中');
        expect(tester.takeException(), isNull, reason: '$label：无 RenderFlex 溢出/异常');
      }
    });

    testWidgets('系统字号 1.3× 不裁切：标题与两栏条目完整落在气泡可视区内', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      setPortrait(tester);
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage();
      await pumpPlayer(tester, engine: engine, storage: storage);

      // 大字下竖屏仍一屏放得下：每段文本都在可视区内（不是树里有、屏上裁掉）。
      for (final (label, finder) in [
        ('标题', title),
        ('副标题', find.text(subtitle)),
        ('左栏标题', noTitle),
        ('右栏标题', yesTitle),
        for (final item in noItems) ('左栏条目：$item', find.text(item)),
        for (final item in yesItems) ('右栏条目：$item', find.text(item)),
      ]) {
        expect(finder, findsOneWidget, reason: '1.3× 下在场：$label');
        expectFullyInsideBubble(tester, finder, label);
      }
      expect(tester.takeException(), isNull, reason: '大字下无裁切/溢出');
    });

    testWidgets('横屏 + 系统字号 1.3×（唯一会顶到的情况）：气泡收进留边内、内部滚动兜底', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      setLandscape(tester);
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage();
      await pumpPlayer(tester, engine: engine, storage: storage);

      const screenHeight = 1264 / 3.5;
      final bubble = tester.getRect(viewport);
      expect(
        bubble.top,
        greaterThanOrEqualTo(kNoticeCardScreenInsetV - 0.5),
        reason: '气泡上缘不越上留边',
      );
      expect(
        bubble.bottom,
        lessThanOrEqualTo(screenHeight - kNoticeCardScreenInsetV + 0.5),
        reason: '气泡最大高 = 屏高 − 上下留边',
      );
      expect(bubble.center.dy, moreOrLessEquals(screenHeight / 2, epsilon: 0.5), reason: '居中');
      expect(title, findsOneWidget);
      // 内容确实超出气泡最大高 → 内部滚动兜底（不是被裁掉）。
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('mirror_question_scrim')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        scrollable.position.maxScrollExtent,
        greaterThan(0),
        reason: '内容超出时在气泡内部滚动',
      );
      expect(tester.takeException(), isNull, reason: '顶到时不溢出/不裁切（内部滚动兜底）');
    });
  });

  group('再次打开：按历史应用并提示', () {
    testWidgets('历史镜像开启：不询问，自动应用并提示「已按历史应用镜像」，短暂后消失', (tester) async {
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: true)],
        ),
      );
      await pumpPlayer(tester, engine: engine, storage: storage);

      expect(find.text('需要镜像吗？'), findsNothing, reason: '按历史应用，无需确认');
      expect(find.byKey(const Key('mirror_history_hint')), findsOneWidget);
      expect(find.text('已按历史应用镜像'), findsOneWidget);
      expect(find.byKey(const Key('mirrored_surface')), findsOneWidget);

      // 提示短暂展示后自动消失。
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('mirror_history_hint')), findsNothing);
    });

    testWidgets('历史镜像关闭：自动应用（不翻转）并提示', (tester) async {
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: false)],
        ),
      );
      await pumpPlayer(tester, engine: engine, storage: storage);

      expect(find.text('需要镜像吗？'), findsNothing);
      expect(find.byKey(const Key('mirror_history_hint')), findsOneWidget);
      expect(find.text('已按历史应用镜像'), findsOneWidget);
      expect(find.byKey(const Key('mirrored_surface')), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('mirror_history_hint')), findsNothing);
    });
  });

  group('打开读标记文件两个开关的真值', () {
    /// 标记文件（v3）的 meta 段：只声明被测的两个开关。
    Map<String, dynamic> markersMeta({
      required bool mirrored,
      required bool localMirrorEnabled,
    }) =>
        {
          'version': 8,
          'meta': {
            'mirrored': mirrored,
            'localMirrorEnabled': localMirrorEnabled,
          },
        };

    testWidgets('全局镜像：markers 真值优先于 index 过渡值（双写通路的读侧闭环）', (tester) async {
      final engine = FakePlaybackEngine();
      // index 过渡值是关、标记文件真值是开 → 画面翻转。
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: false)],
        ),
      );
      await pumpPlayer(
        tester,
        engine: engine,
        storage: storage,
        markers: markersMeta(mirrored: true, localMirrorEnabled: true),
      );

      expect(find.byKey(const Key('mirrored_surface')), findsOneWidget);
      expect(find.text('需要镜像吗？'), findsNothing, reason: 'markers 存在即直接应用');
      // 同步规则：markers 真值回写 index 缓存（内存存储以微任务完成）。
      await tester.pump();
      expect(
        storage.current.entries.single.mirrored,
        isTrue,
        reason: 'markers 真值回写 index 缓存',
      );
    });

    testWidgets('局部镜像总开关：markers 真值关 → 值道为关（片段覆盖位置也不反相）', (tester) async {
      final engine = FakePlaybackEngine();
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: false)],
        ),
      );
      await pumpPlayer(
        tester,
        engine: engine,
        storage: storage,
        markers: markersMeta(mirrored: false, localMirrorEnabled: false),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

      expect(container.read(localMirrorEnabledProvider), isFalse);
      expect(find.byKey(const Key('mirrored_surface')), findsNothing);
    });
  });

  group('打开失败', () {
    testWidgets('打开失败时不弹镜像询问（避免叠在错误提示上）', (tester) async {
      final engine = _ThrowingOpenEngine();
      final storage = InMemoryVideoIndexStorage();
      await pumpPlayer(tester, engine: engine, storage: storage);

      expect(find.text('视频打开失败'), findsOneWidget);
      expect(find.text('需要镜像吗？'), findsNothing);
    });
  });

  group('渲染生效：翻转门读当前位置处有效镜像（位置即真值）', () {
    /// 断言画面当前是否以水平镜像 Transform 呈现。
    bool surfaceMirrored(WidgetTester tester) =>
        find.byKey(const Key('mirrored_surface')).evaluate().isNotEmpty;

    /// 把播放头定格到 [position]（暂停态 seek → 引擎补发位置事件 → 翻转
    /// 门按当前位置重判）并重建一帧。
    Future<void> pauseAt(WidgetTester tester, FakePlaybackEngine engine,
        Duration position) async {
      await engine.pause(); // 停 ticker，位置由显式 seek 精确驱动
      await engine.seek(position);
      await tester.pump();
    }

    testWidgets('全局关：播放头进入启用片段区间画面反相、离开恢复（暂停定格同判）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: false)],
        ),
      );
      await pumpPlayer(tester, engine: engine, storage: storage);

      // 全局镜像关 + 无片段 → 画面不翻转。
      expect(surfaceMirrored(tester), isFalse);

      // 会话内放置一条启用片段（占位网格起点吸拍、默认宽一"八拍"）。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );
      final editor = container.read(annotationEditorProvider);
      final outcome = editor.submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 2)),
      );
      expect(outcome.applied, isTrue);
      final fragment = container.read(localMirrorFragmentsProvider).single;
      expect(fragment.endMs > fragment.startMs, isTrue);

      // 定格在片段右端（半开不含右端 = 区间外）→ 保持全局镜像（不翻转）。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.endMs));
      expect(surfaceMirrored(tester), isFalse);
      // 定格在片段起点（含 = 区间内）→ 反相为翻转。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.startMs));
      expect(surfaceMirrored(tester), isTrue);
      // 离开片段 → 恢复不翻转。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.endMs));
      expect(surfaceMirrored(tester), isFalse);

      // 源视频文件字节不变（翻转是渲染层 Transform，不写源文件）。
      expect(sourceFile.readAsBytesSync(), [1, 2, 3]);
    });

    testWidgets('全局开：片段区间内反镜像关闭；总开关关后画面恢复', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: true)],
        ),
      );
      await pumpPlayer(tester, engine: engine, storage: storage);

      // 全局镜像开 → 初始画面翻转。
      expect(surfaceMirrored(tester), isTrue);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );
      final editor = container.read(annotationEditorProvider);
      editor.submit(const AddLocalMirrorFragment(at: Duration(seconds: 2)));
      final fragment = container.read(localMirrorFragmentsProvider).single;

      // 全局开 + 片段覆盖 → 有效镜像 = 开 ⊕ 覆盖 = 关 → 画面恢复不翻转。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.startMs));
      expect(surfaceMirrored(tester), isFalse);
      // 区间外 → 保持全局开 → 翻转。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.endMs));
      expect(surfaceMirrored(tester), isTrue);

      // 切总开关关：片段不再影响画面（区间内仍按全局开 → 翻转）。
      container.read(localMirrorEnabledProvider.notifier).replace(false);
      await tester.pump();
      await pauseAt(tester, engine, Duration(milliseconds: fragment.startMs));
      expect(surfaceMirrored(tester), isTrue);
    });

    testWidgets('局部镜像总开关关：片段覆盖位置也不翻转；再开立即恢复', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: false)],
        ),
      );
      await pumpPlayer(tester, engine: engine, storage: storage);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );
      final editor = container.read(annotationEditorProvider);
      final outcome = editor.submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 2)),
      );
      expect(outcome.applied, isTrue);
      final fragment = container.read(localMirrorFragmentsProvider).single;

      // 总开关开（缺省）+ 定格片段内 → 反相翻转（既有行为）。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.startMs));
      expect(surfaceMirrored(tester), isTrue);

      // 总开关切关：片段只作轨道标注，定格片段内也按全局镜像（不翻转）。
      container.read(localMirrorEnabledProvider.notifier).replace(false);
      await tester.pump();
      expect(container.read(localMirrorEnabledProvider), isFalse);
      expect(surfaceMirrored(tester), isFalse);

      // 拖动定格到片段外再回片段内，期间总开关关 → 恒按全局（不翻转）。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.endMs));
      expect(surfaceMirrored(tester), isFalse);
      await pauseAt(tester, engine, Duration(milliseconds: fragment.startMs));
      expect(surfaceMirrored(tester), isFalse);

      // 总开关再开：位置不变、立即恢复反相。
      container.read(localMirrorEnabledProvider.notifier).replace(true);
      await tester.pump();
      expect(surfaceMirrored(tester), isTrue);
    });

    testWidgets('播放中进入/离开启用片段区间画面反相/恢复（非暂停，位置流推进驱动）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: false)],
        ),
      );
      await pumpPlayer(tester, engine: engine, storage: storage);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );
      final editor = container.read(annotationEditorProvider);
      // 占位网格（默认 120bpm，八拍 = 4s）下在 8s 处创建 → 片段 [8000,12000)。
      final outcome = editor.submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 8)),
      );
      expect(outcome.applied, isTrue);
      final fragment = container.read(localMirrorFragmentsProvider).single;

      // 先暂停定格在片段起点前（区间外）：不翻转。
      await pauseAt(
        tester,
        engine,
        Duration(milliseconds: fragment.startMs - 10),
      );
      expect(surfaceMirrored(tester), isFalse);

      // 起播：位置流逐步推进穿过片段 → 进入即反相。
      await engine.play();
      await tester.pump(const Duration(milliseconds: 150)); // ≥1 个 100ms 拍
      expect(engine.position.inMilliseconds > fragment.startMs, isTrue,
          reason: '播放应已推进进片段区间内');
      expect(surfaceMirrored(tester), isTrue);

      // 继续播放越过片段右端 → 离开即恢复。
      await tester.pump(const Duration(seconds: 5));
      expect(engine.position.inMilliseconds >= fragment.endMs, isTrue,
          reason: '播放应已推进越过片段右端');
      expect(surfaceMirrored(tester), isFalse);

      expect(sourceFile.readAsBytesSync(), [1, 2, 3]);
    });

    testWidgets('翻转态切换不重建画面控件（surface 元素复用，避免黑屏闪）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: false)],
        ),
      );
      await pumpPlayer(tester, engine: engine, storage: storage);
      expect(surfaceMirrored(tester), isFalse);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );
      final editor = container.read(annotationEditorProvider);
      editor.submit(const AddLocalMirrorFragment(at: Duration(seconds: 2)));
      final fragment = container.read(localMirrorFragmentsProvider).single;

      final surfaceFinder = find.byType(VideoSurfacePlaceholder);
      final elementBefore = tester.element(surfaceFinder);

      // 定格进启用片段 → 翻转为 on（画面子树从「裸宿主」切到「Transform 包裹」）。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.startMs));
      expect(surfaceMirrored(tester), isTrue);
      // 离开片段 → 翻转为 off（切回「裸宿主」）。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.endMs));
      expect(surfaceMirrored(tester), isFalse);

      // 反复跨界不应重建画面控件：同一 Element（其 State/纹理）全程复用——
      // 若被销毁重建（黑屏闪根因）则元素身份会变化。
      final elementAfter = tester.element(surfaceFinder);
      expect(elementAfter, same(elementBefore), reason: '翻转切换不得重建画面控件元素');
      expect(sourceFile.readAsBytesSync(), [1, 2, 3]);
    });

    testWidgets('多片段并集覆盖正确：任一启用片段区间内均翻转、空隙不翻转', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: false)],
        ),
      );
      await pumpPlayer(tester, engine: engine, storage: storage);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );
      final editor = container.read(annotationEditorProvider);
      // 占位网格下两段片段：[8000,12000) 与 [20000,24000)。
      editor.submit(const AddLocalMirrorFragment(at: Duration(seconds: 8)));
      editor.submit(const AddLocalMirrorFragment(at: Duration(seconds: 20)));
      final fragments = container.read(localMirrorFragmentsProvider);
      expect(fragments, hasLength(2));

      // 停在第一段内 → 翻转；两段间空隙 → 不翻转；停在第二段内 → 翻转。
      await pauseAt(tester, engine, Duration(milliseconds: fragments[0].startMs));
      expect(surfaceMirrored(tester), isTrue);
      final gap = (fragments[0].endMs + fragments[1].startMs) ~/ 2;
      await pauseAt(tester, engine, Duration(milliseconds: gap));
      expect(surfaceMirrored(tester), isFalse);
      await pauseAt(tester, engine, Duration(milliseconds: fragments[1].startMs));
      expect(surfaceMirrored(tester), isTrue);
    });
  });

  group('备注贴纸随面（注解层与画面件同一处装配）', () {
    /// 贴在画面左侧的那条备注：镜像时贴纸应换到画面右侧等距处。
    const leftNote = NoteSticker(
      startMs: 1000,
      endMs: 9000,
      text: '这里注意手',
      geometry: NoteGeometry(centerX: 0.25, centerY: 0.4),
    );

    /// 标记文件：备注段就位（几何为视频内容矩形归一化坐标）。
    Map<String, dynamic> markersWithNote({required bool mirrored}) => {
      'version': 8,
      'meta': {'mirrored': mirrored, 'localMirrorEnabled': true},
      'notes': {
        'notes': [
          for (final note in const [leftNote]) note.toJson(),
        ],
      },
    };

    /// 贴纸在屏幕上的水平中心（渲染层真值）。
    double stickerCenterX(WidgetTester tester) =>
        tester.getRect(find.byType(NoteStickerText)).center.dx;

    /// 把播放头定格到 [position] 并重建一帧（暂停态 seek）。
    Future<void> pauseAt(
      WidgetTester tester,
      FakePlaybackEngine engine,
      Duration position,
    ) async {
      await engine.pause();
      await engine.seek(position);
      await tester.pump();
    }

    testWidgets('全局镜像开：贴纸随画面翻到对侧等距处（渲染层两路同源）', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(minutes: 1),
        videoAspectRatio: 2,
      );
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: true)],
        ),
      );
      await pumpPlayer(
        tester,
        engine: engine,
        storage: storage,
        markers: markersWithNote(mirrored: true),
        // 打开恢复的内容哈希校验桩：备注段经恢复编排水合（videoId='seeded'）。
        hasher: const FixedHasher('hash-1'),
      );
      // 播放头落进备注时间窗（窗内才渲染贴纸）。
      await pauseAt(tester, engine, const Duration(milliseconds: 3000));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );
      expect(container.read(noteStickersProvider).single, leftNote);
      expect(
        find.byKey(const Key('mirrored_surface')),
        findsOneWidget,
        reason: '全局镜像开 → 画面翻转',
      );

      // 画面已翻：贴纸按面方向换算，画面上呈现的是它未镜像时落点的镜像。
      final box = tester.getRect(find.byType(PlayerPage));
      final shown = stickerCenterX(tester);
      final unmirrored = noteStickerRect(
        geometry: leftNote.geometry,
        contentRect: box,
        stickerSize: tester.getSize(find.byType(NoteStickerText)),
        faceDirection: FaceDirection.original,
      ).center.dx;
      expect(
        shown - box.left,
        moreOrLessEquals(box.right - unmirrored, epsilon: 0.5),
        reason: '贴纸随画面翻到对侧等距处（不是留在原位置）',
      );
      expect(
        shown,
        isNot(moreOrLessEquals(unmirrored, epsilon: 0.5)),
        reason: '确有换算，不是画在一处',
      );
    });

    testWidgets('进出局部镜像片段：贴纸随该刻方向实时换算（半开两端与窗外同判）',
        (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(minutes: 1),
        videoAspectRatio: 2,
      );
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [historyEntry(filePath: sourceFile.path, videoId: 'hash-1', mirrored: false)],
        ),
      );
      await pumpPlayer(
        tester,
        engine: engine,
        storage: storage,
        markers: markersWithNote(mirrored: false),
        // 打开恢复的内容哈希校验桩：备注段经恢复编排水合（videoId='seeded'）。
        hasher: const FixedHasher('hash-1'),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );
      final editor = container.read(annotationEditorProvider);
      // 占位网格起点的片段：区间为 [4000, 8000)，覆盖备注时间窗。
      editor.submit(const AddLocalMirrorFragment(at: Duration(seconds: 2)));
      final fragment = container.read(localMirrorFragmentsProvider).single;
      expect(fragment.startMs, 4000);
      expect(fragment.endMs, 8000);

      final box = tester.getRect(find.byType(PlayerPage));
      await pauseAt(tester, engine, const Duration(milliseconds: 6000));
      final inside = stickerCenterX(tester);
      expect(find.byKey(const Key('mirrored_surface')), findsOneWidget);
      expect(find.byType(NoteStickerText), findsOneWidget);

      // 片段起点当刻已生效（含）、终点当刻不生效（半开不含），两端贴纸
      // 各随该刻方向换边。
      await pauseAt(
        tester,
        engine,
        Duration(milliseconds: fragment.startMs - 1),
      );
      expect(find.byKey(const Key('mirrored_surface')), findsNothing);
      final outside = stickerCenterX(tester);
      expect(
        outside - box.left,
        moreOrLessEquals(box.right - inside, epsilon: 0.5),
        reason: '出片段即随画面回到未反相的一侧',
      );

      // 片段终点当刻不生效（半开不含）：仍按全局镜像（原相侧）。
      await pauseAt(tester, engine, Duration(milliseconds: fragment.endMs));
      expect(find.byKey(const Key('mirrored_surface')), findsNothing);
      expect(stickerCenterX(tester), moreOrLessEquals(outside, epsilon: 0.5));

      // 窗外（备注时间窗之外）：贴纸不渲染——方向换算不改变显隐。
      await pauseAt(tester, engine, const Duration(milliseconds: 20000));
      expect(find.byType(NoteStickerText), findsNothing);
    });
  });
}



/// 打开即抛错的测试引擎（覆盖 FakePlaybackEngine 的 open 行为）。
class _ThrowingOpenEngine extends FakePlaybackEngine {
  @override
  Future<void> open(Uri source, {bool play = false}) async {
    throw StateError('模拟打开失败');
  }
}
