import 'dart:math' show max;
import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('音源段注册表', () {
    test('注册表项完整：普通 9 槽资产与段内拍点标记齐备', () {
      final normal = metronomeSourceEntryOfId('normal');
      expect(normal.id, 'normal');
      expect(normal.label, '普通');
      expect(normal.available, isTrue);
      // 段内拍点标记：短敲击采样段首即拍点（波形 onset 实测 <1ms，取 0）。
      expect([
        for (final s in normal.speedGroups.single.slots) s.markerMs,
      ], List.filled(9, 0));
    });

    test('人声/歌姬 available:false（待支持置灰占位，无资产）', () {
      for (final id in ['vocal', 'geigi']) {
        final entry = metronomeSourceEntryOfId(id);
        expect(entry.available, isFalse, reason: id);
        expect(entry.label, isNotEmpty, reason: id);
        // 占位项 9 槽落位齐备（采样内容属内容侧另期），available:false 门控。
        expect(
          [for (final s in entry.speedGroups.single.slots) s.asset],
          List.filled(9, ''),
          reason: id,
        );
      }
      // 占位段无资产，不入预载清单；清单按（资产+标记）去重、首次出现定序。
      expect(
        [for (final spec in metronomeSourceRegistryAssets) spec.asset],
        [
          'assets/sounds/metronome_strong.wav',
          'assets/sounds/metronome_beat.wav',
          'assets/sounds/metronome_half.wav',
        ],
      );
    });

    test('未知 id 兜底回普通（旧数据/非法 soundType 不致崩）', () {
      expect(metronomeSourceEntryOfId('nope').id, 'normal');
    });
  });

  group('音源三层结构', () {
    /// 段槽位语义映射：号 1/5 → 重音资产、其余整拍 →
    /// 整拍资产、半拍 → 半拍。按字面书写，不循环生成。
    const normalSlotAssets = [
      'assets/sounds/metronome_strong.wav', // count1
      'assets/sounds/metronome_beat.wav', // count2
      'assets/sounds/metronome_beat.wav', // count3
      'assets/sounds/metronome_beat.wav', // count4
      'assets/sounds/metronome_strong.wav', // count5
      'assets/sounds/metronome_beat.wav', // count6
      'assets/sounds/metronome_beat.wav', // count7
      'assets/sounds/metronome_beat.wav', // count8
      'assets/sounds/metronome_half.wav', // half
    ];

    test('「普通」音源声明 1 个速度组，9 槽按裁决数据映射', () {
      final normal = metronomeSourceEntryOfId('normal');
      expect(normal.mode, MetronomeSlotMode.effect);
      expect(normal.speedGroups.length, 1);
      final group = normal.speedGroups.single;
      expect([for (final s in group.slots) s.asset], normalSlotAssets);
      // 段内拍点标记：短敲击采样段首即拍点。
      expect([for (final s in group.slots) s.markerMs], List.filled(9, 0));
      expect(group.standardMs, 70);
    });

    test('待支持音源：占位速度组恒非空（9 个空资产槽）', () {
      for (final id in ['vocal', 'geigi']) {
        final entry = metronomeSourceEntryOfId(id);
        expect(entry.mode, MetronomeSlotMode.numbered, reason: id);
        expect(entry.speedGroups, hasLength(1), reason: id);
        expect(
          [for (final s in entry.speedGroups.single.slots) s.asset],
          List.filled(9, ''),
          reason: id,
        );
      }
    });

    test('段表：「普通」9 槽去重压平为 3 段，顺序与今天逐位相同', () {
      final table = MetronomeSegmentTable.of(
        metronomeSourceEntryOfId('normal'),
      );
      expect(table.loads.map((s) => s.asset).toList(), [
        'assets/sounds/metronome_strong.wav',
        'assets/sounds/metronome_beat.wav',
        'assets/sounds/metronome_half.wav',
      ]);
      expect(table.loads.map((s) => s.markerMs).toList(), [0, 0, 0]);
      // 槽 → 段 id 查表：号 1/5 槽共用重音资产段（id 0），其余整拍槽共用
      // 整拍段（id 1），半拍槽 = 半拍段（id 2）。
      expect(table.idOf(0, MetronomeSegmentSlot.count1), 0);
      expect(table.idOf(0, MetronomeSegmentSlot.count5), 0);
      for (final slot in [
        MetronomeSegmentSlot.count2,
        MetronomeSegmentSlot.count3,
        MetronomeSegmentSlot.count4,
        MetronomeSegmentSlot.count6,
        MetronomeSegmentSlot.count7,
        MetronomeSegmentSlot.count8,
      ]) {
        expect(table.idOf(0, slot), 1, reason: '$slot');
      }
      expect(table.idOf(0, MetronomeSegmentSlot.half), 2);
    });

    test('段表：多速度组同资产段去重（按 资产+标记 首次出现定序）', () {
      const shared = SegmentSpec(asset: 'a.wav', markerMs: 0);
      const marked = SegmentSpec(asset: 'a.wav', markerMs: 7);
      const other = SegmentSpec(asset: 'b.wav', markerMs: 0);
      final entry = MetronomeSourceEntry(
        id: 'x',
        label: 'x',
        available: true,
        mode: MetronomeSlotMode.effect,
        speedGroups: [
          MetronomeSpeedGroup(
            standardMs: 100,
            slots: [
              shared,
              marked,
              shared,
              shared,
              shared,
              shared,
              shared,
              shared,
              other,
            ],
          ),
          MetronomeSpeedGroup(
            standardMs: 200,
            slots: [
              shared,
              shared,
              marked,
              other,
              shared,
              shared,
              shared,
              shared,
              shared,
            ],
          ),
        ],
      );
      final table = MetronomeSegmentTable.of(entry);
      // 首次出现定序：shared、marked、other。
      expect(table.loads, [shared, marked, other]);
      expect(table.idOf(0, MetronomeSegmentSlot.count1), 0);
      expect(table.idOf(0, MetronomeSegmentSlot.count2), 1);
      expect(table.idOf(0, MetronomeSegmentSlot.half), 2);
      expect(table.idOf(1, MetronomeSegmentSlot.count3), 1);
      expect(table.idOf(1, MetronomeSegmentSlot.count4), 2);
      expect(table.idOf(1, MetronomeSegmentSlot.count5), 0);
    });

    test('注册表不变量：每组恒 9 项、同源组身份互异、声明长度==组内最长段实测长度、最坏音源所需段数 ≤ 原生容量', () async {
      // 原生段槽容量由注册表派生（单份事实源；原生按此容量校验）。
      final nativeCapacity = kMetronomeNativeSegmentCapacity;

      // 实测段长度：测试自解析 WAV 头（独立书写，不复用实现解码）。
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

      for (final entry in metronomeSourceRegistry) {
        expect(entry.speedGroups, isNotEmpty, reason: entry.id);
        for (final group in entry.speedGroups) {
          expect(group.slots, hasLength(9), reason: entry.id);
        }
        final standards = entry.speedGroups.map((g) => g.standardMs).toSet();
        expect(standards.length, entry.speedGroups.length, reason: entry.id);

        final table = MetronomeSegmentTable.of(entry);
        expect(
          table.loads.length,
          lessThanOrEqualTo(nativeCapacity),
          reason: entry.id,
        );
        // 声明长度 == 组内最长段实测长度（资产随包内置，逐段实测）。
        if (!entry.available) continue;
        for (final group in entry.speedGroups) {
          var longest = 0;
          for (final spec in group.slots) {
            if (spec.asset.isEmpty) continue;
            final data = await rootBundle.load(spec.asset);
            longest = max(
              longest,
              measuredMs(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              ),
            );
          }
          expect(group.standardMs, longest, reason: entry.id);
        }
      }
    });
  });
}
