/// 起录武装与前言的纯域换算直测（① 素材与片段面）：武装点 = 起录点 − 余量
/// （钳到有效区间头）；片段入点 = 前言长度（钳到素材全长）。零框架依赖、
/// 不启动 widget 环境。
library;

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:flutter_test/flutter_test.dart';

MaterialRecord _material({int durationMs = 10500, int sourceStartMs = 10000}) =>
    MaterialRecord(
      id: 'm1',
      videoId: 'v1',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      durationMs: durationMs,
      sourceStartMs: sourceStartMs,
      fileName: 'take.mp4',
      sizeBytes: 1,
    );

void main() {
  group('起录武装点换算', () {
    test('武装点 = 起录点 − 余量（默认约 600ms）', () {
      expect(kRecordingArmMarginMs, 600);
      expect(
        computeRecordingArmPoint(startPointMs: 10000, rangeStartMs: 0),
        9400,
      );
    });

    test('起点前余量不足：钳到有效区间头（不越过区间头）', () {
      expect(
        computeRecordingArmPoint(startPointMs: 10000, rangeStartMs: 9800),
        9800,
      );
    });

    test('起点即区间头：无余量可退，武装点 = 起录点（无前导路径）', () {
      expect(
        computeRecordingArmPoint(startPointMs: 10000, rangeStartMs: 10000),
        10000,
      );
    });

    test('余量可调（常量不是规格真理）：按传入余量退，仍受区间头钳制', () {
      expect(
        computeRecordingArmPoint(
          startPointMs: 20000,
          rangeStartMs: 0,
          armMarginMs: 1200,
        ),
        18800,
      );
      expect(
        computeRecordingArmPoint(
          startPointMs: 20000,
          rangeStartMs: 19400,
          armMarginMs: 1200,
        ),
        19400,
        reason: '余量再大也不越过有效区间头',
      );
    });
  });

  group('片段入点换算', () {
    test('入点 = 前言长度（素材内偏移）', () {
      expect(practiceClipInMs(preambleMs: 600, materialDurationMs: 10500), 600);
    });

    test('无前言：入点 0（整段从素材头开始）', () {
      expect(practiceClipInMs(preambleMs: 0, materialDurationMs: 9000), 0);
    });

    test('前言超过素材真实编码时长：钳到素材全长（不越过素材尾）', () {
      expect(practiceClipInMs(preambleMs: 600, materialDurationMs: 400), 400);
    });
  });

  group('录制完成即在轨片段：前言留在素材里、不进片段定义', () {
    test('入点 = 前言长度、出点 = 素材全长，片段范围正好从起录点开始', () {
      final clip = PracticeClip.fullLength(
        id: 'c1',
        material: _material(),
        preambleMs: 600,
      );
      expect(clip.inMs, 600);
      expect(clip.outMs, 10500);
      expect(clip.materialDurationMs, 10500);
      // 唯一对齐锚点 = 起录点：10s 起、到 10s +（10500 − 600）。
      expect(clip.sourceStartMs, 10000);
      expect(clip.sourceEndMs, 19900);
    });

    test('无前言：与既有 1:1 全长片段逐位一致', () {
      final clip = PracticeClip.fullLength(id: 'c1', material: _material());
      expect(clip.inMs, 0);
      expect(clip.outMs, 10500);
      expect(clip.sourceStartMs, 10000);
      expect(clip.sourceEndMs, 20500);
    });

    test('素材原点贴近零且前言更长：素材内偏移不出现负值', () {
      final clip = PracticeClip.fullLength(
        id: 'c1',
        material: _material(durationMs: 3000, sourceStartMs: 200),
        preambleMs: 600,
      );
      expect(clip.materialSourceStartMs, 0);
      expect(clip.sourceStartMs, 600);
      expect(clip.sourceEndMs, 3000);
    });
  });
}
