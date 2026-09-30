import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/core/system_page_text_colors.dart';
import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/share/dance_share.dart';
import 'package:dance_learning_app/share/dance_share_sheet.dart';
import 'package:dance_learning_app/share/outbound_scheme_id.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_share_channel.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/poll.dart';

/// 分享面部件测试：三项勾选与默认值、递出的是哪个
/// 文件的路径（Fake 注入下）、包内内容按勾选装入、接近 1 GB 提示且不阻止、
/// 失败出声。原生面板能否调起归真机验收，不在本套件。
void main() {
  late Directory tempDir;
  late File sourceVideo;
  late Directory materialsBase;
  late FakeShareChannel channel;
  late InMemoryVideoDocumentStorage documents;
  late MemoryManifestStorage manifestStorage;

  final markersJson = <String, Object?>{
    'version': 9,
    'meta': <String, Object?>{
      'signature': <String, Object?>{'song': '海草舞'},
      // 源画面取景选区：随分享包原文带走。
      'framingSelection': <String, Object?>{
        'left': 0.2,
        'top': 0.1,
        'right': 0.7,
        'bottom': 0.6,
      },
    },
  };

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('share_sheet_test');
    sourceVideo = File('${tempDir.path}/source.mp4')
      ..writeAsBytesSync(List.filled(64, 1));
    materialsBase = Directory('${tempDir.path}/materials/v1')
      ..createSync(recursive: true);
    File('${materialsBase.path}/rec_1.mp4').writeAsBytesSync(List.filled(32, 2));
    channel = FakeShareChannel();
    documents = InMemoryVideoDocumentStorage(markers: markersJson);
    manifestStorage = MemoryManifestStorage();
    await manifestStorage.save(<String, Object?>{
      'version': 2,
      'materials': <String, Object?>{
        'entries': <Object?>[
          <String, Object?>{
            'id': 'm1',
            'videoId': 'v1',
            'createdAtMs': 0,
            'durationMs': 8000,
            'sourceStartMs': 1000,
            'fileName': 'rec_1.mp4',
            'sizeBytes': 32,
          },
        ],
      },
    });
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  DanceSnapshot snapshot({int sizeBytes = 64}) => composeDanceSnapshot(
        entry: VideoIndexEntry(
          videoId: 'v1',
          displayName: 'dance_v1.mp4',
          filePath: sourceVideo.path,
          sizeBytes: sizeBytes,
          fastKey: 'k',
          mirrored: false,
          lastOpenedAt: DateTime(2026, 9, 1),
        ),
        importOrder: 0,
        markers: MarkersDocument(
          rangeEndMs: 24000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
          signature: const SongSignature(song: '海草舞'),
        ),
        local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
        practice: const DancePracticeTotals(),
      );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required DanceSnapshot dance,
    bool initialIncludeSourceVideo = true,
    bool initialIncludeMastery = false,
    List<String> initialClipIds = const <String>[],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (_) => documents,
          ),
          materialsBaseDirectoryProvider.overrideWithValue(
            () async => Directory('${tempDir.path}/materials'),
          ),
          materialManifestStoreProvider.overrideWith(
            (ref) => MaterialManifestStore(manifestStorage),
          ),
          shareChannelProvider.overrideWithValue(channel),
          susumeShareDirectoryProvider.overrideWith(
            (ref) async => Directory('${tempDir.path}/out'),
          ),
          outboundSchemeIdStoreProvider.overrideWithValue(
            OutboundSchemeIdFileStore(File('${tempDir.path}/scheme_ids.json')),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: const SizedBox())),
      ),
    );
    // 经路由推入分享面：成功递出后的关闭走真实 pop 路径。
    tester.state<NavigatorState>(find.byType(Navigator)).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: DanceShareSheet(
            dance: dance,
            initialIncludeSourceVideo: initialIncludeSourceVideo,
            initialIncludeMastery: initialIncludeMastery,
            initialClipIds: initialClipIds,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Checkbox findCheckbox(WidgetTester tester, String key) =>
      tester.widget<Checkbox>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Checkbox),
        ),
      );

  /// 确认递出：点击与后续真实装配/递出都在真实事件循环内完成（沿
  /// import_flow_test 的 runAsync 先例）；轮询等待递出完成或失败出声，
  /// 避免真实 IO 与 fake 时钟竞态。
  Future<void> sendSheet(WidgetTester tester) => tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('share_sheet_send')));
        await pollUntil(
          () =>
              channel.sharedFiles.isNotEmpty ||
              find.byType(SnackBar).evaluate().isNotEmpty,
          onTick: tester.pump,
          reason: '确认递出后应出包或出声',
        );
        await tester.pumpAndSettle();
      });

  testWidgets('三项默认勾选：源视频勾、熟练度与练习录像不勾', (tester) async {
    await pumpSheet(tester, dance: snapshot());
    expect(findCheckbox(tester, 'share_sheet_source_video').value, isTrue);
    expect(findCheckbox(tester, 'share_sheet_mastery').value, isFalse);
    expect(findCheckbox(tester, 'share_sheet_clips_m1').value, isFalse);
    // 包体预检默认可见（源视频默认勾）。
    expect(find.byKey(const Key('share_sheet_size')), findsOneWidget);
    expect(find.byKey(const Key('share_sheet_size_warning')), findsNothing);
    await tester.tap(find.byKey(const Key('share_sheet_mastery')));
    await tester.pumpAndSettle();
  });

  testWidgets('默认勾选下确认：递出 <歌名>.susume 原文件路径；包内只含我的标注、无熟练度', (tester) async {
    await pumpSheet(tester, dance: snapshot());
    await sendSheet(tester);

    expect(channel.sharedFiles, hasLength(1));
    final shared = channel.sharedFiles.single;
    expect(shared.path, endsWith('海草舞.susume'));
    expect(Directory('${tempDir.path}/out').existsSync(), isTrue);

    final parsed =
        (await tester.runAsync(() => readSusumePackage(shared.path)))!;
    expect(parsed.manifest.videoId, 'v1');
    expect(parsed.manifest.schemeName, '海草舞');
    expect(parsed.manifest.mastery, isNull);
    expect(parsed.markers, markersJson);
    // 只装了源视频副本，练习录像未勾不装。
    expect(parsed.manifest.media, hasLength(1));
    expect(parsed.manifest.media.single.kind, SusumeMediaKind.sourceVideo);
    expect(parsed.manifest.media.single.fileName, 'source.mp4');
  });

  testWidgets('勾上熟练度与练习录像：包内带逐段档位与录像副本', (tester) async {
    await pumpSheet(tester, dance: snapshot());
    await tester.tap(find.byKey(const Key('share_sheet_mastery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share_sheet_clips_m1')));
    await tester.pumpAndSettle();
    await sendSheet(tester);

    final parsed =
        (await tester.runAsync(() => readSusumePackage(channel.sharedFiles.single.path)))!;
    // 档位 4 = LearningMastery.mastered。
    expect(parsed.manifest.mastery, {0: 4});
    expect(parsed.manifest.media, hasLength(2));
    expect(
      parsed.manifest.media.map((m) => m.kind).toSet(),
      {SusumeMediaKind.sourceVideo, SusumeMediaKind.practiceClip},
    );
  });

  testWidgets('包体接近微信 1 GB 上限给出明确提示，且不阻止递出', (tester) async {
    // 源视频按 900 MB 量级计（索引条目大小 + 清单内媒体大小）。
    await pumpSheet(tester, dance: snapshot(sizeBytes: kSusumeSizeWarnBytes));
    expect(find.byKey(const Key('share_sheet_size_warning')), findsOneWidget);
    // 警告文字取系统页 token：不再用压在白底
    // 上只有 3.2:1 的 deepOrange 原档；token 取值本身的达标由
    // `test/core/contrast_test.dart` 按同一份对比度判定断言。
    final warning = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('share_sheet_size_warning')),
        matching: find.byType(Text),
      ),
    );
    expect(warning.style?.color, kShareWarningTextColor);

    await sendSheet(tester);
    expect(channel.sharedFiles, hasLength(1));
  });

  testWidgets('递出失败出声（SnackBar），不静默、不关面', (tester) async {
    channel.throwOnShare = Exception('no chooser');
    await pumpSheet(tester, dance: snapshot());
    await sendSheet(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byKey(const Key('share_sheet')), findsOneWidget);
    expect(channel.sharedFiles, isEmpty);
  });

  testWidgets('同一支舞两次分享：递出两个包、方案标识一致', (tester) async {
    await pumpSheet(tester, dance: snapshot());
    await sendSheet(tester);
    final first =
        (await tester.runAsync(() => readSusumePackage(channel.sharedFiles[0].path)))!;

    // 面已关，重新打开一份新面再分享一次。
    channel.sharedFiles.clear();
    await pumpSheet(tester, dance: snapshot());
    await sendSheet(tester);
    final second =
        (await tester.runAsync(() => readSusumePackage(channel.sharedFiles.single.path)))!;

    expect(first.manifest.schemeId, second.manifest.schemeId);
  });

  testWidgets('素材库入口初始勾选：源视频不勾、熟练度与指定录像勾', (tester) async {
    await pumpSheet(
      tester,
      dance: snapshot(),
      initialIncludeSourceVideo: false,
      initialIncludeMastery: true,
      initialClipIds: const ['m1'],
    );
    expect(findCheckbox(tester, 'share_sheet_source_video').value, isFalse);
    expect(findCheckbox(tester, 'share_sheet_mastery').value, isTrue);
    expect(findCheckbox(tester, 'share_sheet_clips_m1').value, isTrue);
  });

  testWidgets('素材库入口按初始勾选递出：包内带熟练度与该条录像、不带源视频', (tester) async {
    await pumpSheet(
      tester,
      dance: snapshot(),
      initialIncludeSourceVideo: false,
      initialIncludeMastery: true,
      initialClipIds: const ['m1'],
    );
    await sendSheet(tester);

    expect(channel.sharedFiles, hasLength(1));
    final parsed = (await tester.runAsync(
      () => readSusumePackage(channel.sharedFiles.single.path),
    ))!;
    // 档位 4 = LearningMastery.mastered。
    expect(parsed.manifest.mastery, {0: 4});
    expect(parsed.manifest.media, hasLength(1));
    expect(parsed.manifest.media.single.kind, SusumeMediaKind.practiceClip);
    expect(parsed.manifest.media.single.fileName, 'rec_1.mp4');
  });
}
