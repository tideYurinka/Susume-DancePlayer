import 'dart:io';

import 'package:dance_learning_app/core/system_page_text_colors.dart';
import 'package:dance_learning_app/home/home_page.dart';
import 'package:dance_learning_app/import/import_providers.dart'
    show videoIndexStoreProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/package/whole_machine_backup.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/share/dance_share.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_share_channel.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/poll.dart';

/// 备份入口与备份面部件测试：
/// 首页 ⋯ 有「备份」且可达；备份面媒体默认不勾、言明练舞统计与四拍桶随包
/// 走；确认后经分享通道递出的是一个可解析的整机包（含统计与桶）。递出后
/// 系统面板的表现归真机验收。
void main() {
  late Directory tempDir;
  late File sourceVideo;
  late FakeShareChannel channel;
  late InMemoryVideoIndexStorage indexStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_sheet_test');
    sourceVideo = File('${tempDir.path}/v1.mp4')
      ..writeAsBytesSync(List.filled(64, 1));
    channel = FakeShareChannel();
    indexStore = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [
          VideoIndexEntry(
            videoId: 'v1',
            displayName: 'v1.mp4',
            filePath: sourceVideo.path,
            sizeBytes: 64,
            fastKey: 'k',
            mirrored: false,
            lastOpenedAt: DateTime(2026, 9, 15, 8),
          ),
        ],
      ),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shareChannelProvider.overrideWithValue(channel),
          videoIndexStoreProvider.overrideWithValue(indexStore),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (_) => InMemoryVideoDocumentStorage(
              markers: {
                'version': 8,
                'meta': {
                  'signature': {'song': '海草舞'},
                },
              },
              local: {
                'version': 3,
                'session': {
                  'mastery': {'0': 3},
                },
              },
            ),
          ),
          practiceStatsStoreProvider.overrideWithValue(
            PracticeStatsStore(InMemoryPracticeStatsStorage()),
          ),
          backupPortsProvider.overrideWithValue(
            BackupPorts(
              loadIndexJson: () async => {
                'version': 1,
                'entries': [
                  {'videoId': 'v1', 'filePath': sourceVideo.path},
                ],
              },
              loadIndex: () => indexStore.load(),
              documentStorageFor: (_) => InMemoryVideoDocumentStorage(
                markers: {
                  'version': 8,
                  'meta': {
                    'signature': {'song': '海草舞'},
                  },
                },
                local: {
                  'version': 3,
                  'session': {
                    'mastery': {'0': 3},
                  },
                },
              ),
              memberSchemeStorageFor: (_) => InMemoryMemberSchemeStorage(),
              loadBucketShardJson: (_) async => {
                'version': 1,
                'ledger': {
                  'days': {
                    '2026-09-15': {
                      '4': {'wallSeconds': 12.5, 'sweeps': 2},
                    },
                  },
                },
              },
              loadPracticeStatsJson: () async => {
                'version': 3,
                'sessions': [
                  {'videoId': 'v1', 'wallSeconds': 60.0},
                ],
              },
              loadPracticePlanJson: () async => {
                'version': 1,
                'entries': [
                  {
                    'videoId': 'v1',
                    'ddl': {'date': '2026-10-01'},
                  },
                ],
              },
              loadDeviceSettings: () async => {'mirrorDefault': true},
              loadMaterialsManifestJson: () async => null,
              loadMaterialRecords: () async => const [],
              materialsBaseDirectory: () async =>
                  Directory('${tempDir.path}/materials'),
            ),
          ),
          susumeShareDirectoryProvider.overrideWith(
            (ref) async => Directory('${tempDir.path}/out'),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 打开 ⋯ → 备份面（真实事件循环内点按）。
  Future<void> openBackupSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('home_more_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup_menu_item')));
    await tester.pumpAndSettle();
  }

  testWidgets('首页 ⋯ 有「备份」且可达；备份面言明统计与桶随包走、媒体默认不勾', (tester) async {
    await pumpHome(tester);
    await openBackupSheet(tester);

    expect(find.byKey(const Key('backup_sheet')), findsOneWidget);
    expect(find.byKey(const Key('backup_sheet_stats_note')), findsOneWidget);
    // 说明文字取系统页 token：不再硬编码
    // Colors.green（绕过 token、无深色变体）；token 取值本身的达标由
    // `test/core/contrast_test.dart` 按同一份对比度判定断言。
    final note = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('backup_sheet_stats_note')),
        matching: find.byType(Text),
      ),
    );
    expect(note.style?.color, kBackupNoteTextColor);
    // 钉死新文案：旧的「不在包里」说法在，或新说法被删，这条都会红。
    expect(find.text('练舞统计与四拍桶明细随包走，换机恢复后统计完整'), findsOneWidget);
    expect(find.textContaining('不在备份包里'), findsNothing);
    final media = tester.widget<CheckboxListTile>(
      find.byKey(const Key('backup_sheet_media')),
    );
    expect(media.value, isFalse);
  });

  testWidgets('确认备份：递出的包能解析回来、是整机形态且不含媒体', (tester) async {
    await pumpHome(tester);
    await openBackupSheet(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('backup_sheet_send')));
      await pollUntil(
        () =>
            channel.sharedFiles.isNotEmpty ||
            find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: tester.pump,
        reason: '确认备份后应出包或出声',
      );
    });
    await tester.pumpAndSettle();

    expect(channel.sharedFiles, hasLength(1));
    final shared = channel.sharedFiles.single;
    final parsed = (await tester.runAsync(
      () => readSusumePackage(shared.path),
    ))!;
    expect(parsed.isBackup, isTrue);
    expect(parsed.manifest.media, isEmpty);
    final backup = parsed.backup!;
    expect(backup['payloadVersion'], 3);
    expect(backup['device'], {'mirrorDefault': true});
    expect(
      (backup['practiceStats'] as Map<String, Object?>)['sessions'],
      isNotEmpty,
      reason: '练舞统计进包',
    );
    expect(backup['practicePlan'], isNotEmpty, reason: '计划文档进包');
    final dances = backup['dances'] as List<Object?>;
    expect(dances, hasLength(1));
    final dance = dances.single as Map<String, Object?>;
    expect(dance['videoId'], 'v1');
    expect(dance['buckets'], isNotEmpty, reason: '四拍桶分片进包');
    expect((dance['markers'] as Map<String, Object?>)['meta'], {
      'signature': {'song': '海草舞'},
    });
    expect((dance['local'] as Map<String, Object?>)['session'], {
      'mastery': {'0': 3},
    });
  });

  testWidgets('递出失败出声（SnackBar），面不关', (tester) async {
    channel.throwOnShare = Exception('no chooser');
    await pumpHome(tester);
    await openBackupSheet(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('backup_sheet_send')));
      await pollUntil(
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: tester.pump,
        reason: '备份失败应出声',
      );
    });
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byKey(const Key('backup_sheet')), findsOneWidget);
    expect(channel.sharedFiles, isEmpty);
  });
}
