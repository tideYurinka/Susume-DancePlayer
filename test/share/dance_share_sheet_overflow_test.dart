import 'dart:io';

import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/share/dance_share.dart';
import 'package:dance_learning_app/share/dance_share_sheet.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_share_channel.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/memory_manifest_storage.dart';

/// 分享面：素材勾选区长时可滚动，「分享」按钮
/// 始终可达——素材条数多 + 大字号下对话框内容不把按钮挤出屏幕。
void main() {
  testWidgets('素材多 + 大字号：勾选列表滚动，「分享」按钮完整落在屏内', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(361, 781); // 合成档 361×781dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tempDir = Directory.systemTemp.createTempSync(
      'share_sheet_overflow_test',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final markersJson = <String, Object?>{
      'version': 8,
      'meta': <String, Object?>{
        'signature': <String, Object?>{'song': '海草舞'},
      },
    };
    const clipCount = 20;
    final manifestStorage = MemoryManifestStorage();
    await manifestStorage.save(<String, Object?>{
      'version': 2,
      'materials': <String, Object?>{
        'entries': <Object?>[
          for (var i = 1; i <= clipCount; i++)
            <String, Object?>{
              'id': 'm$i',
              'videoId': 'v1',
              'createdAtMs': 0,
              'durationMs': 8000,
              'sourceStartMs': 1000 * i,
              'fileName': 'rec_$i.mp4',
              'sizeBytes': 32,
            },
        ],
      },
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (_) => InMemoryVideoDocumentStorage(markers: markersJson),
          ),
          materialsBaseDirectoryProvider.overrideWithValue(
            () async => Directory('${tempDir.path}/materials'),
          ),
          materialManifestStoreProvider.overrideWith(
            (ref) => MaterialManifestStore(manifestStorage),
          ),
          shareChannelProvider.overrideWithValue(FakeShareChannel()),
          susumeShareDirectoryProvider.overrideWith(
            (ref) async => Directory('${tempDir.path}/out'),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: const SizedBox())),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: DanceShareSheet(
                dance: composeDanceSnapshot(
                  entry: VideoIndexEntry(
                    videoId: 'v1',
                    displayName: 'dance_v1.mp4',
                    filePath: '${tempDir.path}/source.mp4',
                    sizeBytes: 64,
                    fastKey: 'k',
                    mirrored: false,
                    lastOpenedAt: DateTime(2026, 9, 1),
                  ),
                  importOrder: 0,
                  markers: MarkersDocument(
                    rangeEndMs: 24000,
                    segmentLines: const [
                      SegmentLine(position: Duration(seconds: 8)),
                    ],
                    signature: const SongSignature(song: '海草舞'),
                  ),
                  local: const LocalDocument(),
                  practice: const DancePracticeTotals(),
                ),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('share_sheet_clips_');
      }),
      findsNWidgets(clipCount),
      reason: '素材勾选项全部在场',
    );
    expect(tester.takeException(), isNull, reason: '多素材 + 大字号下无溢出');

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final send = tester.getRect(find.byKey(const Key('share_sheet_send')));
    expect(
      send.bottom,
      lessThanOrEqualTo(screenHeight),
      reason: '「分享」按钮不越下缘（始终可达）',
    );
    expect(send.top, greaterThanOrEqualTo(0), reason: '「分享」按钮不越上缘');
  });
}
