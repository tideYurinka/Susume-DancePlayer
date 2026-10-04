import 'dart:async';

import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_private_json_storage.dart';

/// 每一次读写都抛错的私密存储（模拟无平台通道）。
class _FailingPrivateJsonStorage implements PrivateJsonStorage {
  @override
  Future<Map<String, dynamic>> read() async => throw StateError('无平台通道');

  @override
  Future<void> write(Map<String, dynamic> json) async =>
      throw StateError('无平台通道');

  @override
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    mutate,
  ) async => throw StateError('无平台通道');
}

/// 记读次数的私密存储（钉住读面的 IO 形状：一次问全表）。
class _CountingPrivateJsonStorage implements PrivateJsonStorage {
  _CountingPrivateJsonStorage(this._inner);

  final PrivateJsonStorage _inner;

  int reads = 0;

  @override
  Future<Map<String, dynamic>> read() {
    reads += 1;
    return _inner.read();
  }

  @override
  Future<void> write(Map<String, dynamic> json) => _inner.write(json);

  @override
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    mutate,
  ) => _inner.mutate(mutate);
}

void main() {
  test('缺省：14 个状态位全部按「未看过」', () async {
    final store = OnboardingStore(InMemoryPrivateJsonStorage());

    final seen = await store.loadSeenUnits();
    for (final unitId in onboardingFlagFields.keys) {
      expect(seen.contains(unitId), isFalse, reason: unitId);
    }
  });

  test('缺字段按「未看过」：只有部分字段为真', () async {
    final store = OnboardingStore(
      InMemoryPrivateJsonStorage(
        initial: const {
          'onboarding': {'firstRun': true},
        },
      ),
    );

    final seen = await store.loadSeenUnits();
    expect(seen.contains('first_run'), isTrue);
    expect(seen.contains('download_card'), isFalse);
  });

  test('写入与读回：14 个字段逐一置位', () async {
    final storage = InMemoryPrivateJsonStorage();
    final store = OnboardingStore(storage);

    for (final unitId in onboardingFlagFields.keys) {
      await store.markUnitSeen(unitId);
    }
    expect(await store.loadSeenUnits(), onboardingFlagFields.keys.toSet());

    // 落盘形态：顶层 `onboarding` 对象、14 个布尔字段（状态位 schema）。
    final flags = storage.snapshot['onboarding'] as Map;
    expect(flags.keys.toSet(), onboardingFlagFields.values.toSet());
    expect(flags.values.every((v) => v == true), isTrue);
  });

  test('全表读一次：loadSeenUnits 一次读盘问全表，不按单元逐次读', () async {
    final counting = _CountingPrivateJsonStorage(
      InMemoryPrivateJsonStorage(
        initial: const {
          'onboarding': {'firstRun': true, 'badgeSpeed': true},
        },
      ),
    );
    final store = OnboardingStore(counting);

    final seen = await store.loadSeenUnits();

    expect(seen, {'first_run', 'badge_speed'});
    expect(counting.reads, 1);
  });

  test('读损坏对象按「未看过」兜底，不抛错', () async {
    final store = OnboardingStore(
      InMemoryPrivateJsonStorage(initial: const {'onboarding': 'not-a-map'}),
    );

    expect(await store.loadSeenUnits(), isEmpty);
  });

  test('字段清单以注册表的引导单元表为准：单元表增项即增字段', () {
    expect(
      onboardingFlagFields.keys.toSet(),
      helpGuideUnits.map((u) => u.id).toSet(),
      reason: '状态位字段与引导单元一一对应',
    );
    expect(onboardingFlagFields.length, helpGuideUnits.length);
  });

  test('状态位字段数与引导单元数一致（14）', () {
    expect(onboardingFlagFields.length, helpGuideUnits.length);
    expect(onboardingFlagFields.length, 14);
  });

  test('状态位 schema：新增 / 改名 / 保留的字段名逐位一致', () {
    expect(onboardingFlagFields[practiceRangeUnitId], 'practiceRange');
    expect(onboardingFlagFields[badgeAvSyncUnitId], 'badgeAvSync');
    expect(onboardingFlagFields[badgeRosterUnitId], 'badgeRoster');
    expect(onboardingFlagFields[badgeSpeedUnitId], 'badgeSpeed');
    expect(onboardingFlagFields[badgeLocalMirrorUnitId], 'badgeLocalMirror');
    expect(onboardingFlagFields[badgeSegmentFlagUnitId], 'badgeSegmentFlag');
    expect(
      onboardingFlagFields[badgeThreeFingerJumpUnitId],
      'badgeThreeFingerJump',
    );
    expect(onboardingFlagFields[badgeHalfBeatUnitId], 'badgeHalfBeat');
  });

  test('清一项：该单元回「未完成」并随即落盘，其余单元与其它字段不变', () async {
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'firstRun': true, 'badgeSpeed': true},
        'mirrorDefault': true,
      },
    );
    final store = OnboardingStore(storage);

    await store.clearUnitSeen('first_run');

    final seen = await store.loadSeenUnits();
    expect(seen.contains('first_run'), isFalse);
    expect(seen.contains('badge_speed'), isTrue);
    final snapshot = storage.snapshot;
    expect((snapshot['onboarding'] as Map)['firstRun'], isFalse);
    expect((snapshot['onboarding'] as Map)['badgeSpeed'], isTrue);
    expect(snapshot['mirrorDefault'], isTrue, reason: '重置只动引导状态位');
  });

  test('清全部：全部单元回「未完成」，字段清单与其它顶层字段不变', () async {
    final storage = InMemoryPrivateJsonStorage(
      initial: {
        'onboarding': {
          for (final field in onboardingFlagFields.values) field: true,
        },
        'mirrorDefault': true,
      },
    );
    final store = OnboardingStore(storage);

    await store.clearAllUnitsSeen();

    final seen = await store.loadSeenUnits();
    for (final unitId in onboardingFlagFields.keys) {
      expect(seen.contains(unitId), isFalse, reason: unitId);
    }
    final snapshot = storage.snapshot;
    expect(
      (snapshot['onboarding'] as Map).keys.toSet(),
      onboardingFlagFields.values.toSet(),
      reason: '清全部只写回既有字段，不增不减',
    );
    expect(
      (snapshot['onboarding'] as Map).values.every((v) => v == false),
      isTrue,
    );
    expect(snapshot['mirrorDefault'], isTrue, reason: '重置只动引导状态位');
  });

  test('无平台通道：置位与清除静默不抛错', () async {
    final store = OnboardingStore(_FailingPrivateJsonStorage());

    await store.markUnitSeen('first_run');
    await store.clearUnitSeen('first_run');
    await store.clearAllUnitsSeen();
  });

  test('老数据带已撤下的 badgeCompare 键：不报错、不迁移、不影响其它字段', () async {
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'firstRun': true, 'badgeCompare': true},
        'mirrorDefault': true,
      },
    );
    final store = OnboardingStore(storage);

    // 已撤单元不再是单元表成员，schema 里也没有它的状态位字段。
    expect(onboardingFlagFields.containsKey('badge_compare'), isFalse);
    expect(await store.loadSeenUnits(), contains('first_run'));

    // 清全部：只写回 14 个既有字段，旧键原样留着（不迁移），其它顶层字段不动。
    await store.clearAllUnitsSeen();

    final snapshot = storage.snapshot;
    final flags = snapshot['onboarding'] as Map;
    expect(flags['badgeCompare'], isTrue, reason: '不迁移、不改写已撤单元的旧键');
    expect(flags['firstRun'], isFalse);
    expect(flags.keys.toSet(), {
      ...onboardingFlagFields.values,
      'badgeCompare',
    });
    expect(snapshot['mirrorDefault'], isTrue, reason: '重置只动引导状态位');
  });
}
