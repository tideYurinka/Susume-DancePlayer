import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/auto_scroll_title.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_video_index_storage.dart';

const longTitle = '「小舞」青春修炼手册超长版教学署名 - 十人队形完整注记版';

Widget host(String text, {double width = 200}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: AutoScrollTitle(
          text: text,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    ),
  );
}

/// 测试面逻辑视口（dpr=1 时物理 = 逻辑；dpr=2 时按 physicalSize/dpr 折算）。
void setViewport(WidgetTester tester, Size physical, double dpr) {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

void main() {
  group('标题自动滚动小部件', () {
    testWidgets('未溢出：单份文本静止、无淡出遮罩', (tester) async {
      setViewport(tester, const Size(600, 800), 1.0);
      await tester.pumpWidget(host('短标题'));
      await tester.pumpAndSettle();

      expect(find.text('短标题'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AutoScrollTitle),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
      final before = tester.getTopLeft(find.text('短标题'));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getTopLeft(find.text('短标题')), before);
    });

    testWidgets('溢出：双份文本循环衔接 + 左右边缘淡出遮罩存在', (tester) async {
      setViewport(tester, const Size(600, 800), 1.0);
      await tester.pumpWidget(host(longTitle));
      await tester.pump();

      expect(find.text(longTitle), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(AutoScrollTitle),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
    });

    testWidgets('滚动匀速向左：1 秒位移 = kTitleAutoScrollSpeed', (tester) async {
      setViewport(tester, const Size(600, 800), 1.0);
      await tester.pumpWidget(host(longTitle));
      await tester.pump();
      final first = find.text(longTitle).first;
      final before = tester.getTopLeft(first);
      await tester.pump(const Duration(seconds: 1));
      final after = tester.getTopLeft(first);
      expect(before.dx - after.dx, closeTo(kTitleAutoScrollSpeed, 2));
    });

    testWidgets('文字变化即时重算：长标题滚动中改短标题 → 停止滚动', (tester) async {
      setViewport(tester, const Size(600, 800), 1.0);
      await tester.pumpWidget(host(longTitle));
      await tester.pump();
      expect(find.text(longTitle), findsNWidgets(2));

      await tester.pumpWidget(host('短标题'));
      await tester.pumpAndSettle();
      expect(find.text('短标题'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AutoScrollTitle),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
    });
  });

  group('控制层顶栏长署名滚动', () {
    VideoIndexEntry entry(String name) {
      return VideoIndexEntry(
        videoId: 'hash-1',
        displayName: name,
        filePath: '/priv/videos/$name',
        sizeBytes: 3,
        fastKey: '3-$name',
        mirrored: false,
        mirrorAsked: true,
        lastOpenedAt: DateTime(2026, 9, 1, 12),
      );
    }

    Future<void> pumpPlayerAt(
      WidgetTester tester, {
      required VideoIndexEntry entry,
    }) async {
      // 底排槽位统一内边距/图标后整排加宽约 48dp：窄视口物理宽
      // 放宽 96（620→668dp 逻辑宽）——刻意放宽的**合成档**（非设备基准，
      // 实际逻辑尺寸 668×360dp），避免底部工具组溢出（窄视口语义不变：
      // 顶栏长署名仍滚动让位）。
      setViewport(tester, const Size(1336, 720), 2.0);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
            systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(initial: VideoIndex(entries: [entry])),
            ),
          ],
          child: MaterialApp(
            home: PlayerPage(
              source: Uri.file('/priv/videos/${entry.displayName}'),
              askNaming: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
    }

    testWidgets('窄视口长署名：启用滚动且不与工具区重叠', (tester) async {
      await pumpPlayerAt(tester, entry: entry('dance-with-very-long-name.mp4'));

      final titleFinder = find.byKey(const Key('control_layer_title'));
      expect(titleFinder, findsOneWidget);
      // 未署名回落「文件名回落名」= 去扩展名（滚动仍启用，两份文本）。
      expect(find.text('dance-with-very-long-name'), findsNWidgets(2));
      final titleRect = tester.getRect(titleFinder);
      final firstToolRect = tester.getRect(find.byKey(const Key('tool_undo')));
      expect(titleRect.right, lessThanOrEqualTo(firstToolRect.left));
    });
  });
}
