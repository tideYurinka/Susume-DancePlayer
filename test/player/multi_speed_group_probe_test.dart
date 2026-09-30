import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/player/beat_schedule.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';
import 'package:dance_learning_app/player/native_scheduled_audio.dart';

import '../helpers/fake_beat_audio_sink.dart';

/// 多速度组探针：两速度组合成音源端到端验证选速与预载。
///
/// 期望独立书写：选速三态与段 id 落点全部按字面书写，装载清单按首次出现
/// 定序逐位写出，不循环生成、不复用实现判定。
void main() {
  // ---- 探针音源（合成资产）：2 组 × 9 槽，3 个跨组共享段 ----
  //
  // 段身份 = (资产, 段内标记)；共享段同名同标记 ⇒ 跨组去重。每组恰一段
  // 最长音频定组身份：慢组 400ms、快组 150ms。
  const slowA1 = SegmentSpec(asset: 'probe/a1.wav', markerMs: 0);
  const sharedS1 = SegmentSpec(asset: 'probe/s1.wav', markerMs: 5);
  const slowA3 = SegmentSpec(asset: 'probe/a3.wav', markerMs: 10);
  const slowA4 = SegmentSpec(asset: 'probe/a4.wav', markerMs: 15);
  const slowA5 = SegmentSpec(asset: 'probe/a5.wav', markerMs: 20);
  const slowA6 = SegmentSpec(asset: 'probe/a6.wav', markerMs: 25);
  const slowA7 = SegmentSpec(asset: 'probe/a7.wav', markerMs: 30);
  const slowA8 = SegmentSpec(asset: 'probe/a8.wav', markerMs: 35);
  const sharedS3 = SegmentSpec(asset: 'probe/s3.wav', markerMs: 40);
  const fastB1 = SegmentSpec(asset: 'probe/b1.wav', markerMs: 45);
  const fastB3 = SegmentSpec(asset: 'probe/b3.wav', markerMs: 50);
  const fastB4 = SegmentSpec(asset: 'probe/b4.wav', markerMs: 55);
  const fastB5 = SegmentSpec(asset: 'probe/b5.wav', markerMs: 60);
  const fastB6 = SegmentSpec(asset: 'probe/b6.wav', markerMs: 65);
  const fastB7 = SegmentSpec(asset: 'probe/b7.wav', markerMs: 70);
  const fastB8 = SegmentSpec(asset: 'probe/b8.wav', markerMs: 75);

  final slowGroup = MetronomeSpeedGroup(
    standardMs: 400,
    slots: [
      slowA1, sharedS1, slowA3, slowA4, slowA5, slowA6, slowA7, slowA8,
      sharedS3,
    ],
  );
  final fastGroup = MetronomeSpeedGroup(
    standardMs: 150,
    slots: [
      fastB1, sharedS1, fastB3, fastB4, fastB5, fastB6, fastB7, fastB8,
      sharedS3,
    ],
  );

  final probeSource = MetronomeSourceEntry(
    id: 'probe',
    label: '探针',
    available: true,
    mode: MetronomeSlotMode.effect,
    speedGroups: [slowGroup, fastGroup],
  );

  final probeTable = MetronomeSegmentTable.of(probeSource);

  // 首次出现定序的装载清单（字面书写，慢组 9 槽在前、快组独有 6 段在后）。
  const expectedLoads = [
    slowA1, sharedS1, slowA3, slowA4, slowA5, slowA6, slowA7, slowA8,
    sharedS3, fastB1, fastB3, fastB4, fastB5, fastB6, fastB7, fastB8,
  ];

  // 合成资产：资产名 → 段长（毫秒）。慢组 a1 = 400 定组身份，快组 b1 =
  // 150 定组身份；共享段同名 ⇒ 同一段音频、同一实测长度。
  const assetDurationMs = {
    'probe/a1.wav': 400,
    'probe/s1.wav': 60,
    'probe/a3.wav': 70,
    'probe/a4.wav': 80,
    'probe/a5.wav': 90,
    'probe/a6.wav': 60,
    'probe/a7.wav': 70,
    'probe/a8.wav': 80,
    'probe/s3.wav': 40,
    'probe/b1.wav': 150,
    'probe/b3.wav': 50,
    'probe/b4.wav': 60,
    'probe/b5.wav': 70,
    'probe/b6.wav': 50,
    'probe/b7.wav': 60,
    'probe/b8.wav': 70,
  };

  // 合成 16-bit 单声道 PCM WAV（时长 = [assetDurationMs] 指定）。
  Uint8List synthWav(int durationMs) {
    const sampleRate = 22050;
    final frameCount = sampleRate * durationMs ~/ 1000;
    final dataBytes = frameCount * 2;
    final bytes = ByteData(44 + dataBytes);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // 单声道
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataBytes, Endian.little);
    for (var i = 0; i < frameCount; i++) {
      bytes.setInt16(44 + i * 2, (i.isEven ? 8000 : -8000), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  // 注入的合成资产装载器（不触 rootBundle / 真实文件系统）。
  Future<ByteData> synthLoader(String asset) async =>
      ByteData.sublistView(synthWav(assetDurationMs[asset]!));

  // 独立书写的 WAV 头解析（与既有注册表用例同一口径，不复用实现解码）：
  // 返回 data 块时长（毫秒）。
  int measuredMs(Uint8List wav) {
    final view = ByteData.sublistView(wav);
    final byteRate = view.getUint32(28, Endian.little);
    var offset = 12;
    while (offset + 8 <= wav.length) {
      final id = String.fromCharCodes(wav.sublist(offset, offset + 4));
      final size = view.getUint32(offset + 4, Endian.little);
      if (id == 'data') return (size / byteRate * 1000).round();
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }
    fail('WAV 缺 data 块');
  }

  BeatScheduleCommand commandOf(int segmentId) => BeatScheduleCommand(
    beatMediaTime: const Duration(seconds: 2),
    segmentId: segmentId,
    volume: 0.5,
  );

  test('选速三态：装得下取最快 / 恰好相等 / 全超取最慢', () {
    // 间隔 500：两组都装得下 → 取最快（快组 150）。
    expect(
      selectMetronomeSpeedGroupIndex(probeSource.speedGroups, 500),
      1,
    );
    // 间隔恰好 150：等于快组声明长度，装得下 → 快组。
    expect(
      selectMetronomeSpeedGroupIndex(probeSource.speedGroups, 150),
      1,
    );
    // 间隔恰好 400：等于慢组声明长度，但快组（150）也装得下且更快 → 快组。
    expect(
      selectMetronomeSpeedGroupIndex(probeSource.speedGroups, 400),
      1,
    );
    // 间隔 100：全超 → 取最慢（慢组 400）。
    expect(
      selectMetronomeSpeedGroupIndex(probeSource.speedGroups, 100),
      0,
    );
  });

  test('每组段 id 落点：槽位 → 去重表下标，跨组共享段同 id', () {
    // 慢组（组 0）：1/5 号共用 a1（id 0），其余整拍落各自段，半拍 = s3。
    expect(probeTable.idOf(0, MetronomeSegmentSlot.count1), 0);
    expect(probeTable.idOf(0, MetronomeSegmentSlot.count2), 1);
    expect(probeTable.idOf(0, MetronomeSegmentSlot.count3), 2);
    expect(probeTable.idOf(0, MetronomeSegmentSlot.count4), 3);
    expect(probeTable.idOf(0, MetronomeSegmentSlot.count5), 4);
    expect(probeTable.idOf(0, MetronomeSegmentSlot.count6), 5);
    expect(probeTable.idOf(0, MetronomeSegmentSlot.count7), 6);
    expect(probeTable.idOf(0, MetronomeSegmentSlot.count8), 7);
    expect(probeTable.idOf(0, MetronomeSegmentSlot.half), 8);
    // 快组（组 1）：共享段（s1、s3）与慢组同 id，独有段接排在后。
    expect(probeTable.idOf(1, MetronomeSegmentSlot.count1), 9);
    expect(probeTable.idOf(1, MetronomeSegmentSlot.count2), 1);
    expect(probeTable.idOf(1, MetronomeSegmentSlot.count3), 10);
    expect(probeTable.idOf(1, MetronomeSegmentSlot.count4), 11);
    expect(probeTable.idOf(1, MetronomeSegmentSlot.count5), 12);
    expect(probeTable.idOf(1, MetronomeSegmentSlot.count6), 13);
    expect(probeTable.idOf(1, MetronomeSegmentSlot.count7), 14);
    expect(probeTable.idOf(1, MetronomeSegmentSlot.count8), 15);
    expect(probeTable.idOf(1, MetronomeSegmentSlot.half), 8);
  });

  test('装载清单覆盖全部速度组、按（资产+标记）去重、顺序稳定', () {
    expect(probeTable.loads, expectedLoads);
    // 稳定：重复构建逐位相同。
    expect(MetronomeSegmentTable.of(probeSource).loads, probeTable.loads);
    // 覆盖：两组每个槽位的 id 都落在清单下标域内。
    for (final slot in MetronomeSegmentSlot.values) {
      expect(probeTable.idOf(0, slot), inInclusiveRange(0, 15), reason: '$slot');
      expect(probeTable.idOf(1, slot), inInclusiveRange(0, 15), reason: '$slot');
    }
  });

  test('探针音源通过注册表不变量：每组 9 槽、组身份互异、声明长度==组内最长段实测长度', () {
    for (final group in probeSource.speedGroups) {
      expect(group.slots, hasLength(9));
    }
    expect(
      probeSource.speedGroups.map((g) => g.standardMs).toSet().length,
      2,
    );
    for (final group in probeSource.speedGroups) {
      final longest = group.slots
          .map((s) => measuredMs(synthWav(assetDurationMs[s.asset]!)))
          .reduce(
            (a, b) => a >= b ? a : b,
          );
      expect(group.standardMs, longest);
    }
  });

  test('端到端：换代换组后零重载、零 flush、零停流，槽位来自新组的同一张已载表',
      () async {
    final sink = FakeBeatAudioSink()
      // 探针 16 段 > 生产注册表派生容量（3）：探针是测试夹具，容量按其
      // 装载清单放宽；生产容量不变量仍由注册表用例钉住。
      ..segmentCapacity = expectedLoads.length;
    final renderer = BeatAudioRenderer(
      sink: sink,
      entry: probeSource,
      loadAsset: synthLoader,
    );

    // 慢组（组 0）拍先响：首条消费指令触发整张去重表一次性装载。
    await renderer.schedule(commandOf(probeTable.idOf(0,
        MetronomeSegmentSlot.count1)));
    expect(sink.loads.map((l) => l.segmentId).toList(),
        [for (var i = 0; i < expectedLoads.length; i++) i]);
    expect(sink.loads.map((l) => l.markerMs).toList(),
        [for (final spec in expectedLoads) spec.markerMs]);
    final loadsAfterSlow = sink.loads.length;
    final startsAfterSlow = sink.startCount;
    final enqueuesAfterSlow = sink.enqueues.length;

    // 网格换代 → 选速落快组（组 1）：只换查表键。
    await renderer.schedule(commandOf(probeTable.idOf(1,
        MetronomeSegmentSlot.count1)));
    await renderer.schedule(commandOf(probeTable.idOf(1,
        MetronomeSegmentSlot.count5)));

    expect(sink.enqueues.length, enqueuesAfterSlow + 2);
    expect(sink.enqueues.last.segmentId, probeTable.idOf(1,
        MetronomeSegmentSlot.count5));
    // 零重载、零 flush、零停流。
    expect(sink.loads.length, loadsAfterSlow, reason: '换组不重载');
    expect(sink.flushCount, 0, reason: '换组不 flush');
    expect(sink.stopCount, 0, reason: '换组不停流');
    expect(sink.startCount, startsAfterSlow, reason: '换组不动流');
    // 新组槽位来自同一张已载表：快组段 id 对应的已载标记 = 快组槽规格。
    final loadedMarkers = {
      for (final load in sink.loads) load.segmentId: load.markerMs,
    };
    for (final slot in MetronomeSegmentSlot.values) {
      expect(
        loadedMarkers[probeTable.idOf(1, slot)],
        fastGroup.slots[slot.index].markerMs,
        reason: '$slot',
      );
    }

    // 再次换代换回慢组（组 0）：同样只换查表键，仍零重载、零 flush。
    await renderer.schedule(commandOf(probeTable.idOf(0,
        MetronomeSegmentSlot.count5)));
    expect(sink.enqueues.last.segmentId, probeTable.idOf(0,
        MetronomeSegmentSlot.count5));
    expect(sink.loads.length, loadsAfterSlow, reason: '换回慢组不重载');
    expect(sink.flushCount, 0, reason: '换回慢组不 flush');
    expect(sink.stopCount, 0, reason: '换回慢组不停流');
  });

  test('会话按档间隔选出的组也在已载清单内', () async {
    final sink = FakeBeatAudioSink()..segmentCapacity = expectedLoads.length;
    final renderer = BeatAudioRenderer(
      sink: sink,
      entry: probeSource,
      loadAsset: synthLoader,
    );
    await renderer.schedule(commandOf(probeTable.idOf(0,
        MetronomeSegmentSlot.count1)));
    final loadedIds = sink.loads.map((l) => l.segmentId).toSet();

    // 会话档间隔 200ms → 选出快组；间隔 450ms → 选出慢组。两组的全部
    // 槽位 id 都已在渲染器装载过的段 id 域内。
    for (final intervalMs in [200, 450]) {
      final group = selectMetronomeSpeedGroupIndex(
        probeSource.speedGroups,
        intervalMs,
      );
      for (final slot in MetronomeSegmentSlot.values) {
        expect(
          loadedIds.contains(probeTable.idOf(group, slot)),
          isTrue,
          reason: '会话间隔 $intervalMs 组 $group 槽 $slot 应已预载',
        );
      }
    }
  });
}
