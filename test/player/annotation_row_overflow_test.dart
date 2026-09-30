import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart'
    show contentHasherProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/control_layer.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/beat_test_seam.dart' show hangingBeatPipeline;
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/pump_past_marquee.dart';
import '../helpers/device_viewport.dart';

/// 标注工具区槽位行：大字号窄竖屏下整行等比
/// 缩小，不溢出、不裁字——与视频工具行同一口径（FittedBox scaleDown）。
void main() {
  testWidgets('竖屏 1.6×：标注工具行不溢出，行宽收进控制层可用宽', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // 竖屏真机基准：1264×2736 @3.5 = 361.1×781.7dp。
    useNamedViewport(tester, ViewportTier.compact);

    final source = Uri.file('/videos/a.mp4');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          cameraCaptureProvider.overrideWithValue(FakeCameraCaptureService()),
          androidCameraPlatform(),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          contentHasherProvider.overrideWithValue(const FixedHasher('vid-a')),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => InMemoryVideoDocumentStorage(),
          ),
          videoDocumentCoordinatorProvider.overrideWith(
            (ref, videoId) =>
                VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
          ),
        ],
        child: MaterialApp(home: PlayerPage(source: source)),
      ),
    );
    await tester.pumpAndSettle();

    // 单击画面唤出控制层（等双击判定窗口过）。
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await pumpPastMarquee(tester);
    expect(find.byKey(const Key('control_layer')), findsOneWidget);

    expect(tester.takeException(), isNull, reason: '1.6× 竖屏下无溢出');

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final row = tester.getRect(
      find.byKey(kAnnotationToolRowKey),
    );
    expect(row.right, lessThanOrEqualTo(screenWidth), reason: '标注工具行不越右缘');
    expect(row.left, greaterThanOrEqualTo(0), reason: '标注工具行不越左缘');
    // 不裁字：槽位标签文本完整在场（整行等比缩小，而非把字裁掉）——
    // 标签矩形完整落在屏内。
    for (final label in ['重点', '分段', '添加', '删除', '自动分段']) {
      expect(find.text(label), findsWidgets, reason: '$label 标签在场');
      final rect = tester.getRect(find.text(label).first);
      expect(rect.right, lessThanOrEqualTo(screenWidth), reason: '$label 不被裁');
      expect(rect.width, greaterThan(0), reason: '$label 有可见宽度');
    }
  });
}
