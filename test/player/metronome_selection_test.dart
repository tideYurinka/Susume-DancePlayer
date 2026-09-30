import 'package:flutter_test/flutter_test.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';

void main() {
  group('选段纯函数', () {
    // 期望按字面书写（期望独立书写，不复用实现判定）。
    test('音效类：恒按拍号取段', () {
      expect(
        selectMetronomeSlot(
          eightCount: 1,
          beatCount: 1,
          mode: MetronomeSlotMode.effect,
        ),
        MetronomeSegmentSlot.count1,
      );
      expect(
        selectMetronomeSlot(
          eightCount: 3,
          beatCount: 5,
          mode: MetronomeSlotMode.effect,
        ),
        MetronomeSegmentSlot.count5,
      );
      expect(
        selectMetronomeSlot(
          eightCount: 8,
          beatCount: 7,
          mode: MetronomeSlotMode.effect,
        ),
        MetronomeSegmentSlot.count7,
      );
    });

    test('按号发音类：小节首（拍号 1）按八拍号，其余按拍号', () {
      expect(
        selectMetronomeSlot(
          eightCount: 2,
          beatCount: 1,
          mode: MetronomeSlotMode.numbered,
        ),
        MetronomeSegmentSlot.count2,
      );
      // 非小节首即使八拍号不同也按拍号。
      expect(
        selectMetronomeSlot(
          eightCount: 3,
          beatCount: 4,
          mode: MetronomeSlotMode.numbered,
        ),
        MetronomeSegmentSlot.count4,
      );
      expect(
        selectMetronomeSlot(
          eightCount: 2,
          beatCount: 5,
          mode: MetronomeSlotMode.numbered,
        ),
        MetronomeSegmentSlot.count5,
      );
    });

    test('八拍号回卷：9 → 1（只朝整拍，绝不落半拍）', () {
      expect(
        selectMetronomeSlot(
          eightCount: 9,
          beatCount: 1,
          mode: MetronomeSlotMode.numbered,
        ),
        MetronomeSegmentSlot.count1,
      );
      expect(
        selectMetronomeSlot(
          eightCount: 17,
          beatCount: 1,
          mode: MetronomeSlotMode.numbered,
        ),
        MetronomeSegmentSlot.count1,
      );
    });

    test('会话路（八拍号恒 1）：小节首恒 count1', () {
      expect(
        selectMetronomeSlot(
          eightCount: 1,
          beatCount: 1,
          mode: MetronomeSlotMode.numbered,
        ),
        MetronomeSegmentSlot.count1,
      );
      // 拍号域恒 1..8，拍号本无回卷；选段返回域也恒整拍槽，永不落半拍。
      expect(
        selectMetronomeSlot(
          eightCount: 4,
          beatCount: 8,
          mode: MetronomeSlotMode.numbered,
        ),
        MetronomeSegmentSlot.count8,
      );
      for (final beatCount in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final slot = selectMetronomeSlot(
          eightCount: 5,
          beatCount: beatCount,
          mode: MetronomeSlotMode.effect,
        );
        expect(slot, isNot(MetronomeSegmentSlot.half));
      }
    });

    test('前导区（八拍号 0）按拍号取样', () {
      expect(
        selectMetronomeSlot(
          eightCount: 0,
          beatCount: 1,
          mode: MetronomeSlotMode.effect,
        ),
        MetronomeSegmentSlot.count1,
      );
      expect(
        selectMetronomeSlot(
          eightCount: 0,
          beatCount: 5,
          mode: MetronomeSlotMode.effect,
        ),
        MetronomeSegmentSlot.count5,
      );
      expect(
        selectMetronomeSlot(
          eightCount: 0,
          beatCount: 5,
          mode: MetronomeSlotMode.numbered,
        ),
        MetronomeSegmentSlot.count5,
      );
    });
  });

  group('选速纯函数', () {
    final groups = <MetronomeSpeedGroup>[
      MetronomeSpeedGroup(standardMs: 300, slots: _emptySlots()),
      MetronomeSpeedGroup(standardMs: 100, slots: _emptySlots()),
      MetronomeSpeedGroup(standardMs: 200, slots: _emptySlots()),
    ];

    int pick(int intervalMs) =>
        selectMetronomeSpeedGroupIndex(groups, intervalMs);

    test('装得下（standardMs ≤ 间隔）的组里取最快一组', () {
      expect(pick(250), 1); // 100 与 200 装得下 → 取最快 100
      expect(pick(1000), 1); // 全装得下 → 取最快 100
      expect(pick(150), 1); // 只有 100 装得下
    });

    test('恰好相等算装得下', () {
      expect(pick(300), 1);
      expect(pick(200), 1);
      expect(pick(100), 1);
    });

    test('全超间隔取最慢一组', () {
      expect(pick(50), 0); // 全都超过 50 → 取最慢 300
      expect(pick(99), 0);
    });

    test('边界：恰好相等的唯一装得下组', () {
      final two = <MetronomeSpeedGroup>[
        MetronomeSpeedGroup(standardMs: 500, slots: _emptySlots()),
        MetronomeSpeedGroup(standardMs: 300, slots: _emptySlots()),
      ];
      expect(selectMetronomeSpeedGroupIndex(two, 300), 1);
      expect(selectMetronomeSpeedGroupIndex(two, 299), 0);
    });
  });
}

List<SegmentSpec> _emptySlots() =>
    List.filled(9, const SegmentSpec(asset: '', markerMs: 0));
