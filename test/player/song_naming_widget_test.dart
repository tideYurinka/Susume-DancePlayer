import 'package:dance_learning_app/core/contrast.dart'
    show meetsContrastFloor;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStorageProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show screenBrightnessControllerProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/player/settings_persistence.dart';
import 'package:dance_learning_app/player/song_naming.dart';
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_key.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 命名对话框与导入命名 / 顶栏改名 widget 测试：经命名会话弹出命名框（初值空 +
/// 保存置灰）、对话框出口语义与保存门、键盘感知形态与横屏浮层单行（保存落在
/// 行尾、切换钮只往返歌曲名/舞者名），以及顶栏标题可点进改名（保存后标题
/// 即时刷新）。域侧判定、提交与署名迁移的断言语义在
/// `test/player/song_naming_session_test.dart` 以模块接口重写。
/// 直接泵对话框（不经播放页——各方向播放器形态在别处覆盖）。
Future<void> pumpDialogAt(WidgetTester tester, Size physicalSize) async {
  tester.view.physicalSize = physicalSize;
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: SongNamingDialog(initialSong: 'dance.mp4')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const filePath = '/priv/videos/dance.mp4';

  VideoIndexEntry unsignedEntry({bool mirrorAsked = true}) {
    return VideoIndexEntry(
      videoId: 'hash-1',
      displayName: 'dance.mp4',
      filePath: filePath,
      sizeBytes: 3,
      fastKey: '3-dance.mp4',
      mirrored: false,
      mirrorAsked: mirrorAsked,
      lastOpenedAt: DateTime(2026, 9, 1, 12),
    );
  }

  VideoIndexEntry signedEntry() {
    return VideoIndexEntry(
      videoId: 'hash-1',
      displayName: 'dance.mp4',
      filePath: filePath,
      sizeBytes: 3,
      fastKey: '3-dance.mp4',
      mirrored: false,
      mirrorAsked: true,
      lastOpenedAt: DateTime(2026, 9, 1, 12),
      signatureCache: const SongSignature(
        dancer: '如',
        song: 'My Love',
        remark: '9人版',
      ),
    );
  }

  Future<(InMemoryVideoIndexStorage, InMemoryVideoDocumentStorage)> pumpPlayer(
    WidgetTester tester, {
    required bool askNaming,
    List<VideoIndexEntry> entries = const [],
    Map<String, dynamic> markers = const {},
    bool markersPresent = false,
    List<dynamic> extraOverrides = const [],
  }) async {
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: entries),
    );
    final docs = InMemoryVideoDocumentStorage(
      markers: markers,
      markersPresent: markersPresent,
    );
    // 顶栏工具随「全局镜像」（原「镜像」加宽）与新增的「局部镜像」
    // 两槽变宽——默认测试视口（800 逻辑宽）已放不下，标题会进滚动态
    // （AutoScrollTitle 循环动画 → pumpAndSettle 不收敛）。本文件关心的是
    // 命名框/署名入口，取与真实横屏设备同量级的视口（dev 机约 995）。
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1920, 1080); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
    tester.view.devicePixelRatio = 2.0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          screenBrightnessControllerProvider.overrideWithValue(
            FakeScreenBrightnessController(),
          ),
          videoIndexStoreProvider.overrideWithValue(index),
          contentHasherProvider.overrideWithValue(const FixedHasher('hash-1')),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => docs,
          ),
          videoDocumentCoordinatorProvider.overrideWith(
            (ref, videoId) => VideoDocumentCoordinator(docs),
          ),
          ...extraOverrides,
        ],
        child: MaterialApp(
          home: PlayerPage(source: Uri.file(filePath), askNaming: askNaming),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (index, docs);
  }

  Future<void> singleTapShowControlLayer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  /// 直接泵命名对话框（不经播放页——控制层窄屏形态在别处覆盖），并关掉
  /// Scaffold 随键盘缩放：真实对话框在 showDialog 覆盖层里、不随 Scaffold
  /// 二次缩，键盘抬升由对话框自身经窗口 viewInsets 负责。
  Future<void> pumpDialog(
    WidgetTester tester, {
    required Size physicalSize,
    String initialSong = '',
    String initialDancer = '',
    String initialRemark = '',
  }) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = physicalSize;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SongNamingDialog(
            initialSong: initialSong,
            initialDancer: initialDancer,
            initialRemark: initialRemark,
            fallbackText: 'dance.mp4',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 经 showDialog 打开命名框并捕获 Navigator.pop 的返回值（出口语义断言）。
  Future<List<SongNamingResult?>> pumpDialogReturning(
    WidgetTester tester, {
    required Size physicalSize,
    String initialSong = '',
    String initialDancer = '',
    String initialRemark = '',
  }) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = physicalSize;
    final results = <SongNamingResult?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showDialog<SongNamingResult>(
                  context: context,
                  builder: (_) => SongNamingDialog(
                    initialSong: initialSong,
                    initialDancer: initialDancer,
                    initialRemark: initialRemark,
                    fallbackText: 'dance.mp4',
                  ),
                );
                results.add(result);
              },
              child: const Text('open_naming'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open_naming'));
    await tester.pumpAndSettle();
    return results;
  }

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const Key('naming_save')))
          .onPressed !=
      null;

  group('导入命名框', () {
    testWidgets('新导入无署名：页面经命名会话弹出命名框，歌曲名初值为空、保存置灰，预览回退文件名', (
      tester,
    ) async {
      await pumpPlayer(tester, askNaming: true, entries: [unsignedEntry()]);

      expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);
      final songField = tester.widget<TextField>(
        find.byKey(const Key('naming_song_field')),
      );
      expect(songField.controller!.text, '');
      // 空歌名 → 保存置灰。
      expect(saveEnabled(tester), isFalse);

      // 预览首行：空歌名显示文件名回退串。
      String previewText() =>
          tester.widget<Text>(find.byKey(const Key('naming_preview'))).data!;
      expect(previewText(), 'dance.mp4');

      // 输入三字段：预览实时更新（歌名仍空 → 整串回退文件名，不含舞者/注记）。
      await tester.enterText(find.byKey(const Key('naming_dancer_field')), '如');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('naming_remark_field')),
        '9人版',
      );
      await tester.pump();
      expect(previewText(), 'dance.mp4');

      // 歌名填入 → 保存可用，预览按真实歌名。
      await tester.enterText(
        find.byKey(const Key('naming_song_field')),
        'My Love',
      );
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
      expect(previewText(), '「如」My Love - 9人版');

      // 保存即经命名会话提交：对话框关闭（提交落盘的净化/双写/迁移断言语义
      // 在 test/player/song_naming_session_test.dart 以域接口重写）。
      await tester.tap(find.byKey(const Key('naming_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('song_naming_dialog')), findsNothing);
    });
  });

  group('命名框出口与保存门', () {
    testWidgets('「跳过」经 Navigator.pop 返回 confirmed:false 与输入框现值', (tester) async {
      final results = await pumpDialogReturning(
        tester,
        physicalSize: const Size(1080, 1920),
        initialSong: '旧名',
        initialDancer: '如',
      );

      await tester.enterText(find.byKey(const Key('naming_song_field')), '改一半');
      await tester.pump();
      await tester.tap(find.byKey(const Key('naming_skip')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('song_naming_dialog')), findsNothing);
      expect(results.single!.confirmed, isFalse);
      expect(
        results.single!.signature,
        const SongSignature(dancer: '如', song: '改一半'),
      );
    });

    testWidgets('空歌名「保存」置灰；填入歌名后可用并返回 confirmed:true', (tester) async {
      final results = await pumpDialogReturning(
        tester,
        physicalSize: const Size(1080, 1920),
      );

      expect(saveEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('naming_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);

      // 纯空白同样不算填了歌名（门 = trim 非空）；「跳过」始终是可走的出路。
      await tester.enterText(find.byKey(const Key('naming_song_field')), '   ');
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
      expect(
        tester.widget<TextButton>(find.byKey(const Key('naming_skip'))).onPressed,
        isNotNull,
      );

      await tester.enterText(find.byKey(const Key('naming_song_field')), 'My Love');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
      await tester.tap(find.byKey(const Key('naming_save')));
      await tester.pumpAndSettle();

      expect(results.single!.confirmed, isTrue);
      expect(results.single!.signature.song, 'My Love');
    });
  });
  group('首次导入的问答次序', () {
    testWidgets('新导入：先出命名框（此时无镜像遮罩），关掉之后才出镜像询问', (tester) async {
      await pumpPlayer(
        tester,
        askNaming: true,
        entries: [unsignedEntry(mirrorAsked: false)],
      );

      expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('mirror_question_scrim')),
        findsNothing,
        reason: '命名框未关：镜像询问尚未开始',
      );
      expect(find.text('需要镜像吗？'), findsNothing);

      // 关掉命名框（跳过 = 按文件名署名，之后不再弹）。
      await tester.tap(find.byKey(const Key('naming_skip')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('song_naming_dialog')), findsNothing);
      expect(
        find.byKey(const Key('mirror_question_scrim')),
        findsOneWidget,
        reason: '跳过命名仍被问镜像',
      );
      expect(find.text('需要镜像吗？'), findsOneWidget);
    });

    testWidgets('新导入：命名框保存后同样被问镜像', (tester) async {
      await pumpPlayer(
        tester,
        askNaming: true,
        entries: [unsignedEntry(mirrorAsked: false)],
      );

      await tester.enterText(
        find.byKey(const Key('naming_song_field')),
        'My Love',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('naming_save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('song_naming_dialog')), findsNothing);
      expect(find.byKey(const Key('mirror_question_scrim')), findsOneWidget);
    });

    testWidgets('老视频（askNaming=false）：命名框从不出现，镜像照旧立即询问', (tester) async {
      await pumpPlayer(
        tester,
        askNaming: false,
        entries: [unsignedEntry(mirrorAsked: false)],
      );

      expect(find.byKey(const Key('song_naming_dialog')), findsNothing);
      expect(find.byKey(const Key('mirror_question_scrim')), findsOneWidget);
      expect(find.text('需要镜像吗？'), findsOneWidget);
    });
  });

  group('键盘感知命名框', () {
    testWidgets('竖屏键盘弹起：完整表单缩到键盘上方、区内滚动、不顶穿溢出', (tester) async {
      // 竖屏物理方向视口（1080x1920 物理 = 360x640 逻辑，测试面 dpr = 3.0）：
      // 形态按物理方向判定，竖屏键盘开保持完整表单。
      await pumpDialog(
        tester,
        physicalSize: const Size(1080, 1920),
        initialSong: 'dance.mp4',
      );

      // FakeViewPadding 为物理像素（测试面 dpr = 3.0）：900 物理 = 300 逻辑。
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 完整表单仍在：顶部栏动作 + 预览 + 三字段。
      expect(find.text('重命名'), findsOneWidget);
      expect(find.byKey(const Key('naming_skip')), findsOneWidget);
      expect(find.byKey(const Key('naming_save')), findsOneWidget);
      expect(find.byKey(const Key('naming_preview')), findsOneWidget);
      expect(find.byKey(const Key('naming_dancer_field')), findsOneWidget);
      expect(find.byKey(const Key('naming_song_field')), findsOneWidget);
      expect(find.byKey(const Key('naming_remark_field')), findsOneWidget);
      // 表单抬升到键盘上方：键盘 insets 经窗口真实值进入布局。
      final inset = tester.widget<Padding>(
        find.byKey(const Key('song_naming_keyboard_inset')),
      );
      expect(inset.padding.resolve(TextDirection.ltr).bottom, 300);
    });

    testWidgets('键盘收起：抬升归零，回到完整表单', (tester) async {
      await pumpDialog(
        tester,
        physicalSize: const Size(1080, 1920),
        initialSong: 'dance.mp4',
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final inset = tester.widget<Padding>(
        find.byKey(const Key('song_naming_keyboard_inset')),
      );
      expect(inset.padding.resolve(TextDirection.ltr).bottom, 0);
      expect(find.byKey(const Key('naming_song_field')), findsOneWidget);
    });

    testWidgets('键盘开 + 极小视口：对话框区内滚动，仍不顶穿溢出', (tester) async {
      // 极小竖屏视口（360 x 400 逻辑像素）。
      await pumpDialog(
        tester,
        physicalSize: const Size(1080, 1200),
        initialSong: 'dance.mp4',
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('naming_save')), findsOneWidget);
      expect(find.byKey(const Key('naming_song_field')), findsOneWidget);
      final inset = tester.widget<Padding>(
        find.byKey(const Key('song_naming_keyboard_inset')),
      );
      expect(inset.padding.resolve(TextDirection.ltr).bottom, 200);
    });

    testWidgets('顶部栏：跳过/保存与标题「重命名」同一行，竖屏分居两端', (tester) async {
      await pumpDialogAt(tester, const Size(1080, 2340));

      final title = tester.getCenter(find.text('重命名'));
      final skip = tester.getCenter(find.byKey(const Key('naming_skip')));
      final save = tester.getCenter(find.byKey(const Key('naming_save')));
      expect(title.dy, closeTo(skip.dy, 1));
      expect(title.dy, closeTo(save.dy, 1));
      expect(skip.dx, lessThan(title.dx));
      expect(save.dx, greaterThan(title.dx));
    });
  });

  group('初值规则：导入空', () {
    testWidgets('导入命名：三字段初值均为空', (tester) async {
      await pumpPlayer(tester, askNaming: true, entries: [unsignedEntry()]);

      expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);
      final song = tester.widget<TextField>(
        find.byKey(const Key('naming_song_field')),
      );
      expect(song.controller!.text, '');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('naming_dancer_field')))
            .controller!
            .text,
        '',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('naming_remark_field')))
            .controller!
            .text,
        '',
      );
    });
  });

  group('进入态：预览取色与初始焦点', () {
    testWidgets('预览行取主题正文色，且在卡底上达标', (tester) async {
      await pumpDialog(
        tester,
        physicalSize: const Size(1080, 1920),
        initialSong: 'My Love',
      );

      final preview = tester.widget<Text>(
        find.byKey(const Key('naming_preview')),
      );
      final colorScheme = Theme.of(
        tester.element(find.byKey(const Key('naming_preview'))),
      ).colorScheme;
      expect(preview.style?.color, colorScheme.onSurface);
      expect(preview.style?.fontSize, 14);
      // 按文字实际压着的底色算（4.5:1 下限）。
      expect(
        meetsContrastFloor(
          preview.style!.color!.toARGB32(),
          colorScheme.surface.toARGB32(),
        ),
        isTrue,
      );
    });

    testWidgets('打开即聚焦歌曲名；光标停在现歌名末尾', (tester) async {
      await pumpDialog(
        tester,
        physicalSize: const Size(1080, 1920),
        initialSong: 'My Love',
      );

      final song = tester.widget<TextField>(
        find.byKey(const Key('naming_song_field')),
      );
      expect(song.focusNode!.hasFocus, isTrue);
      expect(
        song.controller!.selection,
        const TextSelection.collapsed(offset: 'My Love'.length),
      );
      // 另两字段不抢焦点。
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('naming_dancer_field')))
            .focusNode!
            .hasFocus,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('naming_remark_field')))
            .focusNode!
            .hasFocus,
        isFalse,
      );
    });

    testWidgets('导入命名（初值为空）同样落在歌曲名上，光标在 0 位', (tester) async {
      await pumpDialog(tester, physicalSize: const Size(1080, 1920));

      final song = tester.widget<TextField>(
        find.byKey(const Key('naming_song_field')),
      );
      expect(song.focusNode!.hasFocus, isTrue);
      expect(
        song.controller!.selection,
        const TextSelection.collapsed(offset: 0),
      );
    });

    testWidgets('光标的末尾落点只作用于首次聚焦：之后手动切回不受摆布', (tester) async {
      await pumpDialog(
        tester,
        physicalSize: const Size(1080, 1920),
        initialSong: 'My Love',
      );

      final song = tester.widget<TextField>(
        find.byKey(const Key('naming_song_field')),
      );
      song.controller!.selection = const TextSelection.collapsed(offset: 2);
      await tester.showKeyboard(find.byKey(const Key('naming_dancer_field')));
      await tester.pump();
      await tester.showKeyboard(find.byKey(const Key('naming_song_field')));
      await tester.pump();

      expect(song.focusNode!.hasFocus, isTrue);
      expect(
        song.controller!.selection,
        const TextSelection.collapsed(offset: 2),
      );
    });

    testWidgets('横屏打开即聚焦歌曲名：键盘升起后浮层单行就位', (tester) async {
      await pumpDialog(tester, physicalSize: const Size(2400, 1080));

      // 未手点任何字段：只模拟键盘随初始焦点升起。
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('naming_song_field')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(find.byKey(const Key('naming_overlay_row')), findsOneWidget);
    });
  });

  group('顶部栏与字段呈现', () {
    Future<void> openNamingDialog(WidgetTester tester) async {
      await pumpDialog(
        tester,
        physicalSize: const Size(1080, 1920),
        initialSong: 'dance.mp4',
      );
      expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);
    }

    testWidgets('横屏顶部栏：跳过/保存右上并排，与标题同一行', (tester) async {
      await pumpDialogAt(tester, const Size(2340, 1080));

      final title = tester.getCenter(find.text('重命名'));
      final skip = tester.getCenter(find.byKey(const Key('naming_skip')));
      final save = tester.getCenter(find.byKey(const Key('naming_save')));
      expect(title.dy, closeTo(skip.dy, 1));
      expect(title.dy, closeTo(save.dy, 1));
      // 并排右上：跳过在保存左侧，两者都在标题右侧。
      expect(skip.dx, lessThan(save.dx));
      expect(skip.dx, greaterThan(title.dx));
    });

    testWidgets('预览行在表单首行（位于舞者名字段之上）', (tester) async {
      await openNamingDialog(tester);

      final preview = tester.getCenter(find.byKey(const Key('naming_preview')));
      final dancer = tester.getCenter(
        find.byKey(const Key('naming_dancer_field')),
      );
      expect(preview.dy, lessThan(dancer.dy));
    });

    testWidgets('字段短名「舞者名/歌曲名/备注」；舞者名与备注带灰字「可选」', (tester) async {
      await openNamingDialog(tester);

      expect(find.text('舞者名'), findsOneWidget);
      expect(find.text('歌曲名'), findsOneWidget);
      expect(find.text('备注'), findsOneWidget);
      // 选填标注：仅舞者名与备注两个字段带灰字「可选」。
      final optionalGrey = ThemeData().colorScheme.onSurfaceVariant;
      final optionalMarks = tester.widgetList<Text>(find.text('可选'));
      expect(optionalMarks.length, 2);
      for (final mark in optionalMarks) {
        expect(mark.style?.color, optionalGrey);
      }
    });
  });

  group('横屏键盘浮层单行', () {
    /// 横屏物理方向视口（2400x1080 物理 = 800x360 逻辑，测试面 dpr = 3.0）。
    Future<void> pumpLandscapeDialog(WidgetTester tester) async {
      await pumpDialog(tester, physicalSize: const Size(2400, 1080));
    }

    /// 聚焦某字段并模拟键盘弹起（焦点 → 浮层当前字段由 focus listener 决定）。
    Future<void> focusAndRaiseKeyboard(WidgetTester tester, Key field) async {
      await tester.showKeyboard(find.byKey(field));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await tester.pumpAndSettle();
    }

    testWidgets('横屏键盘弹起：浮层单行（字段名｜输入｜切字段钮｜保存），隐藏标题栏与跳过', (tester) async {
      await pumpLandscapeDialog(tester);

      await focusAndRaiseKeyboard(tester, const Key('naming_song_field'));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('naming_overlay_row')), findsOneWidget);
      // 正在编辑歌曲名：切换钮只有一个，指向另一个主字段舞者名。
      expect(find.byKey(const Key('naming_switch_dancer')), findsOneWidget);
      expect(find.byKey(const Key('naming_switch_remark')), findsNothing);
      expect(find.byKey(const Key('naming_song_field')), findsOneWidget);
      // 浮层优先：标题栏、预览与「跳过」隐藏；「保存」落在行尾。
      expect(find.text('重命名'), findsNothing);
      expect(find.byKey(const Key('naming_skip')), findsNothing);
      expect(find.text('跳过'), findsNothing);
      expect(find.byKey(const Key('naming_save')), findsOneWidget);
      expect(find.byKey(const Key('naming_preview')), findsNothing);
    });

    testWidgets('键盘收起：回完整表单（顶部栏 + 预览 + 三字段）', (tester) async {
      await pumpLandscapeDialog(tester);

      await focusAndRaiseKeyboard(tester, const Key('naming_song_field'));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('naming_overlay_row')), findsNothing);
      expect(find.text('重命名'), findsOneWidget);
      expect(find.byKey(const Key('naming_skip')), findsOneWidget);
      expect(find.byKey(const Key('naming_save')), findsOneWidget);
      expect(find.byKey(const Key('naming_preview')), findsOneWidget);
      expect(find.byKey(const Key('naming_dancer_field')), findsOneWidget);
      expect(find.byKey(const Key('naming_song_field')), findsOneWidget);
      expect(find.byKey(const Key('naming_remark_field')), findsOneWidget);
    });

    testWidgets('切换钮只在歌曲名与舞者名之间往返；输入原样保留', (tester) async {
      await pumpLandscapeDialog(tester);

      await focusAndRaiseKeyboard(tester, const Key('naming_song_field'));
      // 当前歌曲名 → 切到舞者名。
      await tester.tap(find.byKey(const Key('naming_switch_dancer')));
      await tester.pumpAndSettle();

      // 键盘 insets 未动（不收起键盘），仍是浮层单行。
      final inset = tester.widget<Padding>(
        find.byKey(const Key('song_naming_keyboard_inset')),
      );
      expect(inset.padding.resolve(TextDirection.ltr).bottom, 300);
      expect(find.byKey(const Key('naming_overlay_row')), findsOneWidget);
      // 现在编辑舞者名：切换钮只有一个，指回歌曲名；备注在浮层内不可达。
      expect(find.byKey(const Key('naming_switch_song')), findsOneWidget);
      expect(find.byKey(const Key('naming_switch_remark')), findsNothing);
      expect(find.byKey(const Key('naming_switch_dancer')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('naming_dancer_field')))
            .focusNode!
            .hasFocus,
        isTrue,
      );

      // 切字段不丢字：两字段各自留值。
      await tester.enterText(find.byKey(const Key('naming_dancer_field')), '如');
      await tester.pump();
      await tester.tap(find.byKey(const Key('naming_switch_song')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('naming_song_field')), 'My Love');
      await tester.pump();
      await tester.tap(find.byKey(const Key('naming_switch_dancer')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('naming_dancer_field')))
            .controller!
            .text,
        '如',
      );
    });

    testWidgets('当前字段为备注（先在完整表单点入）：切换钮指向歌曲名，浮层内不出现备注切换钮', (tester) async {
      await pumpLandscapeDialog(tester);

      await focusAndRaiseKeyboard(tester, const Key('naming_remark_field'));

      expect(find.byKey(const Key('naming_overlay_row')), findsOneWidget);
      expect(find.byKey(const Key('naming_remark_field')), findsOneWidget);
      expect(find.byKey(const Key('naming_switch_song')), findsOneWidget);
      expect(find.byKey(const Key('naming_switch_dancer')), findsNothing);
    });

    testWidgets('浮层内「保存」可达：空歌名置灰，填入后点击即提交（confirmed:true）', (tester) async {
      final (_, docs) = await pumpPlayer(
        tester,
        askNaming: true,
        entries: [unsignedEntry()],
      );
      // 横屏（1920x1080 物理 @2 = 960x540 逻辑）+ 键盘弹起 → 浮层优先。
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('naming_overlay_row')), findsOneWidget);
      expect(find.byKey(const Key('naming_skip')), findsNothing);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(
        find.byKey(const Key('naming_song_field')),
        'My Love',
      );
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
      await tester.tap(find.byKey(const Key('naming_save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('song_naming_dialog')), findsNothing);
      expect(
        MarkersDocument.fromJson(docs.markersSnapshot).signature,
        const SongSignature(song: 'My Love'),
      );
    });
  });

  group('顶栏署名显示与标题改名入口', () {
    String fieldText(WidgetTester tester, String key) =>
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

    /// 泵播放页并种入「该视频已有一笔统计会话 + 一份四拍桶分片」：断言
    /// 改名经域间提交通知的写-through 迁移端到端接线。
    Future<(InMemoryPracticeStatsStorage, InMemoryFourBeatBucketStorage)>
    pumpWithStats(
      WidgetTester tester, {
      required List<VideoIndexEntry> entries,
    }) async {
      final stats = InMemoryPracticeStatsStorage()
        ..rawJson = PracticeStatsDocument(
          sessions: [
            PracticeSessionRecord(
              start: DateTime(2026, 9, 5, 20, 12, 3),
              videoId: 'hash-1',
              signature: const SongSignature(song: 'dance.mp4'),
              wallSeconds: 372.4,
            ),
          ],
        ).toJson();
      final buckets = InMemoryFourBeatBucketStorage()
        ..setRaw(
          'hash-1',
          FourBeatBucketShard(
            signature: const SongSignature(song: 'dance.mp4'),
            days: {
              '2026-09-05': FourBeatBucketDay(
                buckets: {
                  const FourBeatBucketKey(1, 0): const FourBeatBucketValue(
                    wallSeconds: 10,
                    sweeps: 1,
                  ),
                },
              ),
            },
          ).toJson(),
        );
      await pumpPlayer(
        tester,
        askNaming: false,
        entries: entries,
        extraOverrides: [
          practiceStatsStorageProvider.overrideWithValue(stats),
          fourBeatBucketStorageProvider.overrideWithValue(buckets),
        ],
      );
      return (stats, buckets);
    }

    testWidgets('顶栏显示署名显示串；未署名回退文件名', (tester) async {
      await pumpPlayer(tester, askNaming: false, entries: [unsignedEntry()]);
      await singleTapShowControlLayer(tester);
      expect(find.byKey(const Key('control_layer_title')), findsOneWidget);
      expect(find.text('dance.mp4'), findsOneWidget);
    });

    testWidgets('顶栏标题本身即改名入口，标题区内不另设第二枚钮', (tester) async {
      await pumpPlayer(tester, askNaming: false, entries: [unsignedEntry()]);
      await singleTapShowControlLayer(tester);

      final zone = find.byKey(const Key('control_layer_rename'));
      expect(zone, findsOneWidget);
      // 入口就是标题那一行本体（标题 + 尾部铅笔图标）。
      expect(
        find.descendant(
          of: zone,
          matching: find.byKey(const Key('control_layer_title')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: zone,
          matching: find.byIcon(Icons.drive_file_rename_outline),
        ),
        findsOneWidget,
      );
      // 可点语义由标题本体承担：标题区内不再有第二枚按钮件。
      for (final type in [IconButton, TextButton, FilledButton, InkWell]) {
        expect(
          find.descendant(of: zone, matching: find.byType(type)),
          findsNothing,
          reason: '标题区内不另设 $type',
        );
      }
    });

    testWidgets('点标题打开 rename 场景（三字段带当前署名）；保存后标题即时更新、统计署名迁移接线通', (
      tester,
    ) async {
      final (stats, buckets) = await pumpWithStats(
        tester,
        entries: [signedEntry()],
      );
      await singleTapShowControlLayer(tester);
      expect(find.text('「如」My Love - 9人版'), findsOneWidget);

      await tester.tap(find.byKey(const Key('control_layer_rename')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);
      // 改名场景带出现值（非导入的空初值）。
      expect(fieldText(tester, 'naming_song_field'), 'My Love');
      expect(fieldText(tester, 'naming_dancer_field'), '如');
      expect(fieldText(tester, 'naming_remark_field'), '9人版');

      await tester.enterText(
        find.byKey(const Key('naming_song_field')),
        'My Love 2',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('naming_save')));
      // 控制层开着（节拍轨占位动画在跑）——用显式 pump 推完对话框退场。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('song_naming_dialog')), findsNothing);
      // 标题即时刷新（域侧净化/双写断言语义在
      // test/player/song_naming_session_test.dart 重写）。
      expect(find.text('「如」My Love 2 - 9人版'), findsOneWidget);
      // 端到端接线：改名经署名域提交通知把统计与四拍桶分片署名快照都迁移。
      expect(
        stats.document.sessions.single.signature,
        const SongSignature(dancer: '如', song: 'My Love 2', remark: '9人版'),
      );
      expect(
        FourBeatBucketShard.fromJson(buckets.savedJsonFor('hash-1')!).signature,
        const SongSignature(dancer: '如', song: 'My Love 2', remark: '9人版'),
      );
    });

    testWidgets('未署名视频（标题回退文件名）同样可点 = 补命名：初值为文件名', (tester) async {
      await pumpPlayer(tester, askNaming: false, entries: [unsignedEntry()]);
      await singleTapShowControlLayer(tester);
      expect(find.text('dance.mp4'), findsOneWidget);

      await tester.tap(find.byKey(const Key('control_layer_rename')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);
      expect(fieldText(tester, 'naming_song_field'), 'dance.mp4');
      expect(fieldText(tester, 'naming_dancer_field'), isEmpty);
      expect(fieldText(tester, 'naming_remark_field'), isEmpty);

      await tester.enterText(find.byKey(const Key('naming_song_field')), '补命名');
      await tester.pump();
      await tester.tap(find.byKey(const Key('naming_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('补命名'), findsOneWidget);
    });
  });
}
