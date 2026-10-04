import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/player/preview_snap.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/document_grid_of.dart';

void main() {
  group('预览线吸附解析纯函数', () {
    const lines = [
      Duration(seconds: 30),
      Duration(seconds: 60),
      Duration(seconds: 120),
    ];

    test('半径内吸附到最近分段线', () {
      expect(
        resolvePreviewSnap(
          target: const Duration(seconds: 31),
          segmentLines: lines,
          snapRadius: const Duration(seconds: 3),
        ),
        const Duration(seconds: 30),
      );
      // 两条线都在半径内时取更近者。
      expect(
        resolvePreviewSnap(
          target: const Duration(seconds: 58),
          segmentLines: lines,
          snapRadius: const Duration(seconds: 5),
        ),
        const Duration(seconds: 60),
      );
    });

    test('半径外不吸附返回 null', () {
      expect(
        resolvePreviewSnap(
          target: const Duration(seconds: 35),
          segmentLines: lines,
          snapRadius: const Duration(seconds: 3),
        ),
        isNull,
      );
    });

    test('开关关闭短路：直接返回 null（无视半径）', () {
      expect(
        resolvePreviewSnap(
          target: const Duration(seconds: 30),
          segmentLines: lines,
          snapRadius: const Duration(seconds: 3),
          enabled: false,
        ),
        isNull,
      );
    });

    test('只吸附传入的分段线：首/尾线不在入参则不可能被吸附', () {
      // 调用方只传分段线（不含视频首/尾）；函数对 0 与总时长附近的目标
      // 在无邻近分段线时不吸附。
      expect(
        resolvePreviewSnap(
          target: const Duration(milliseconds: 500),
          segmentLines: lines,
          snapRadius: const Duration(seconds: 3),
        ),
        isNull,
      );
      expect(
        resolvePreviewSnap(
          target: const Duration(minutes: 3),
          segmentLines: lines,
          snapRadius: const Duration(seconds: 3),
        ),
        isNull,
      );
    });

    test('无分段线时恒 null', () {
      expect(
        resolvePreviewSnap(
          target: const Duration(seconds: 10),
          segmentLines: const [],
          snapRadius: const Duration(seconds: 3),
        ),
        isNull,
      );
    });

    test('恰好在半径边界上吸附（≤ 半径）', () {
      expect(
        resolvePreviewSnap(
          target: const Duration(seconds: 33),
          segmentLines: lines,
          snapRadius: const Duration(seconds: 3),
        ),
        const Duration(seconds: 30),
      );
    });
  });

  group('预览磁吸目标集（分段线 + 首线 + 尾线）', () {
    test('目标集 = 分段线 + 首线 + 尾线', () {
      expect(
        previewSnapTargetSet(
          segmentLines: const [Duration(seconds: 30), Duration(seconds: 60)],
          rangeStart: const Duration(seconds: 5),
          rangeEnd: const Duration(seconds: 115),
        ),
        const [
          Duration(seconds: 30),
          Duration(seconds: 60),
          Duration(seconds: 5),
          Duration(seconds: 115),
        ],
      );
    });

    test('首/尾传 null：目标集只含分段线（首/尾控制柄拖动语义）', () {
      expect(
        previewSnapTargetSet(
          segmentLines: const [Duration(seconds: 30)],
          rangeStart: null,
          rangeEnd: null,
        ),
        const [Duration(seconds: 30)],
      );
    });

    test('首线与分段线重合时去重（同一目标只出现一次）', () {
      expect(
        previewSnapTargetSet(
          segmentLines: const [Duration(seconds: 5)],
          rangeStart: const Duration(seconds: 5),
          rangeEnd: const Duration(minutes: 1),
        ),
        const [Duration(seconds: 5), Duration(minutes: 1)],
      );
      expect(
        previewSnapTargetSet(
          segmentLines: const [],
          rangeStart: Duration.zero,
          rangeEnd: Duration.zero, // 首尾重合（零长区间）。
        ),
        const [Duration.zero],
      );
    });

    test('半径内取最近者：首线比分段线更近时吸首线', () {
      final targets = previewSnapTargetSet(
        segmentLines: const [Duration(seconds: 30)],
        rangeStart: Duration.zero,
        rangeEnd: const Duration(minutes: 3),
      );
      // 目标 3s：距首线 3s、距分段线 27s → 最近者 = 首线。
      expect(
        resolvePreviewSnap(
          target: const Duration(seconds: 3),
          segmentLines: targets,
          snapRadius: const Duration(seconds: 5),
        ),
        Duration.zero,
      );
      // 目标 28.5s：距分段线 1.5s、距首线 28.5s → 最近者 = 分段线。
      expect(
        resolvePreviewSnap(
          target: const Duration(milliseconds: 28500),
          segmentLines: targets,
          snapRadius: const Duration(seconds: 5),
        ),
        const Duration(seconds: 30),
      );
    });

    test('尾线在半径内可吸附；半径外不吸附', () {
      final targets = previewSnapTargetSet(
        segmentLines: const [],
        rangeStart: Duration.zero,
        rangeEnd: const Duration(minutes: 3),
      );
      expect(
        resolvePreviewSnap(
          target: const Duration(minutes: 3) - const Duration(seconds: 2),
          segmentLines: targets,
          snapRadius: const Duration(seconds: 3),
        ),
        const Duration(minutes: 3),
      );
      expect(
        resolvePreviewSnap(
          target: const Duration(minutes: 3) - const Duration(seconds: 5),
          segmentLines: targets,
          snapRadius: const Duration(seconds: 3),
        ),
        isNull,
      );
    });
  });

  group('拖动 seek 落点解析（待命 × 开关 × 有无目标的穷举）', () {
    // 真实网格：拍点每 0.5s、强拍每 2s（0/2/4…）。
    final downbeatGrid = documentGridOf(uniformDownbeatGridDoc(seconds: 60));
    // 无强拍网格：请求位置无强拍可吸。
    final noDownbeatGrid = documentGridOf(
      marker_doc.BeatGrid(
        model: 'fake.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2024),
        beats: [
          for (var i = 0; i < 8; i++)
            marker_doc.BeatPoint(t: i * 0.5, down: false),
        ],
      ),
    );
    final timeline = AnnotationTimeline.normalized(
      videoDuration: const Duration(seconds: 60),
      segmentLines: const [SegmentLine(position: Duration(seconds: 30))],
    );

    // 半径 = 窗 60s × 12dp / 内容区宽 600px = 1.2s。
    Duration? resolve({
      required Duration target,
      bool standby = false,
      bool enabled = true,
      BeatGrid? grid,
    }) => snapScrubTarget(
      target,
      standby: standby,
      grid: grid ?? downbeatGrid,
      enabled: enabled,
      timeline: timeline,
      windowSpan: const Duration(seconds: 60),
      contentWidth: 600,
    );

    test('待命态：恒定吸最近强拍，开关关闭同样吸（开关不作用于待命态）', () {
      expect(
        resolve(
          target: const Duration(milliseconds: 1400),
          standby: true,
          enabled: false,
        ),
        const Duration(seconds: 2),
      );
      expect(
        resolve(target: const Duration(milliseconds: 3100), standby: true),
        const Duration(seconds: 4),
      );
    });

    test('待命态 + 无强拍：未吸附（落点 = 原目标）', () {
      expect(
        resolve(
          target: const Duration(milliseconds: 1400),
          standby: true,
          grid: noDownbeatGrid,
        ),
        isNull,
      );
    });

    test('开关开：半径内吸最近目标线（分段线 / 首线 / 尾线）', () {
      expect(
        resolve(target: const Duration(milliseconds: 30500)),
        const Duration(seconds: 30),
      );
      expect(resolve(target: const Duration(milliseconds: 800)), Duration.zero);
      expect(
        resolve(target: const Duration(milliseconds: 59500)),
        const Duration(seconds: 60),
      );
    });

    test('目标线恰为原目标：仍算吸附（吸附位不折叠进落点值）', () {
      expect(
        resolve(target: Duration.zero),
        Duration.zero,
        reason: '首线在目标集内且 target 恰落在线上，仍返回吸附命中',
      );
    });

    test('开关开但半径外：未吸附（待命态也不参与）', () {
      expect(resolve(target: const Duration(seconds: 35)), isNull);
    });

    test('开关关：半径内也不吸附', () {
      expect(
        resolve(target: const Duration(milliseconds: 30500), enabled: false),
        isNull,
      );
    });
  });
}
