import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'package:dance_learning_app/player/speed_control.dart';
import 'package:dance_learning_app/player/speed_step.dart';
import 'package:dance_learning_app/player/speed_step_preset.dart';
import 'package:dance_learning_app/player/speed_step_preset_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';

void main() {
  late FakePlaybackEngine engine;
  late InMemoryPrivateJsonStorage storage;
  late ProviderContainer container;

  ProviderContainer makeContainer({required bool restore}) {
    return ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        speedStepPresetStorageProvider
            .overrideWithValue(SpeedStepPresetStore(storage)),
        // 存取 seam 单测不跑自动恢复（恢复行为单独一组验证）。
        if (!restore)
          speedStepPresetAutoRestoreProvider.overrideWithValue(false),
      ],
    );
  }

  setUp(() {
    engine = FakePlaybackEngine();
    storage = InMemoryPrivateJsonStorage();
    container = makeContainer(restore: false);
    addTearDown(container.dispose);
  });

  SpeedStepPresetDoc doc() => container.read(speedStepPresetProvider);
  SpeedStepPresetModel model() =>
      container.read(speedStepPresetProvider.notifier);

  group('预设 Notifier（初始态）', () {
    test('初始：仅两个内置预设、选中首个、参数已应用到步进控制', () {
      expect(doc().presets.map((p) => p.id), ['builtin_first', 'builtin_review']);
      expect(doc().selectedId, 'builtin_first');
      expect(
        container.read(speedControlProvider).stepParams,
        const SpeedStepParams(
          startRate: 0.5,
          maxRate: 1.0,
          lapsPerRate: 3,
          rateIncrement: 0.1,
        ),
      );
    });
  });

  group('选中', () {
    test('选中「复习」：参数应用到步进控制、选中态更新并落盘', () async {
      await model().select('builtin_review');

      expect(doc().selectedId, 'builtin_review');
      expect(
        container.read(speedControlProvider).stepParams,
        const SpeedStepParams(
          startRate: 0.5,
          maxRate: 1.0,
          lapsPerRate: 2,
          rateIncrement: 0.25,
        ),
      );      expect(storage.snapshot['speedStepPresets']['selectedId'],
          'builtin_review');
    });

    test('选中不存在的 id：no-op', () async {
      await model().select('nope');
      expect(doc().selectedId, 'builtin_first');
    });
  });

  group('编辑任意预设', () {
    test('更新未选中预设的 名称+参数：只改该预设、不改选中、不应用参数到步进', () async {
      // 先造一个自定义「复习副本」（未选中，初值同当前选中 builtin_first）。
      await model().createCustom('复习副本');
      final customId = doc().selectedId;
      await model().select('builtin_first');

      await model().updatePreset(
        id: customId,
        name: '冲刺',
        params: const SpeedStepParams(
          startRate: 0.8,
          maxRate: 1.5,
          lapsPerRate: 2,
          rateIncrement: 0.2,
        ),
      );

      final preset = doc().presets.firstWhere((p) => p.id == customId);
      expect(preset.name, '冲刺');
      expect(
        preset.params,
        const SpeedStepParams(
          startRate: 0.8,
          maxRate: 1.5,
          lapsPerRate: 2,
          rateIncrement: 0.2,
        ),
      );
      expect(doc().selectedId, 'builtin_first', reason: '编辑未选中不改选中');
      expect(
        container.read(speedControlProvider).stepParams,
        const SpeedStepParams(),
        reason: '未选中预设的参数不应用到步进控制',
      );
    });

    test('更新选中预设：参数应用到步进控制并落盘', () async {
      await model().updatePreset(
        id: 'builtin_first',
        params: const SpeedStepParams(
          startRate: 0.6,
          maxRate: 1.4,
          lapsPerRate: 1,
          rateIncrement: 0.3,
        ),
      );
      expect(
        container.read(speedControlProvider).stepParams,
        const SpeedStepParams(
          startRate: 0.6,
          maxRate: 1.4,
          lapsPerRate: 1,
          rateIncrement: 0.3,
        ),
      );
      expect(
        (storage.snapshot['speedStepPresets']['presets'] as List)[0]['params']
            ['startRate'],
        0.6,
      );
    });

    test('内置预设可改名改参（开放删除后不变）', () async {
      await model().updatePreset(id: 'builtin_review', name: '精修复习');
      final preset = doc().presets.firstWhere((p) => p.id == 'builtin_review');
      expect(preset.name, '精修复习');
      expect(preset.builtin, isTrue);
    });

    test('空名/纯空白 name：保留原名称（不置空）', () async {
      await model().updatePreset(id: 'builtin_first', name: '   ');
      final preset = doc().presets.firstWhere((p) => p.id == 'builtin_first');
      expect(preset.name, '初见·大量练习');
    });

    test('非法参数忽略（预设与步进参数不变）', () async {
      await model().updatePreset(
        id: 'builtin_first',
        name: 'x',
        params: const SpeedStepParams(startRate: 1.0, maxRate: 0.5),
      );
      expect(
        doc().presets.firstWhere((p) => p.id == 'builtin_first').params,
        const SpeedStepParams(),
      );
      expect(doc().presets.firstWhere((p) => p.id == 'builtin_first').name,
          '初见·大量练习');
    });

    test('不存在的 id：no-op', () async {
      await model().updatePreset(id: 'nope', name: 'x');
      expect(doc().presets.length, 2);
    });
  });

  group('编辑即存（内置覆盖）', () {
    test('修改选中内置预设参数：预设内容更新并落盘、步进参数同步', () async {
      await model().updatePreset(
        id: 'builtin_first',
        params: const SpeedStepParams(
          startRate: 0.4,
          maxRate: 1.2,
          lapsPerRate: 4,
          rateIncrement: 0.2,
        ),
      );

      final selected = doc().presets.firstWhere((p) => p.id == 'builtin_first');
      expect(selected.params.startRate, 0.4);
      expect(selected.params.maxRate, 1.2);
      expect(
        container.read(speedControlProvider).stepParams.startRate,
        0.4,
      );
      final saved = storage.snapshot['speedStepPresets']['presets'] as List;
      expect((saved[0]['params'] as Map)['startRate'], 0.4);
    });

    test('恢复「未选中」的内置预设：其参数回出厂、选中态与步进参数不变', () async {
      await model().select('builtin_review');
      await model().updatePreset(
        id: 'builtin_review',
        params: const SpeedStepParams(
          startRate: 0.9,
          maxRate: 1.4,
          lapsPerRate: 1,
          rateIncrement: 0.2,
        ),
      );

      await model().restoreBuiltinDefault('builtin_first');

      final first = doc().presets.firstWhere((p) => p.id == 'builtin_first');
      expect(first.params, const SpeedStepParams(), reason: '回出厂');
      expect(doc().selectedId, 'builtin_review', reason: '选中态不变');
      expect(
        container.read(speedControlProvider).stepParams.startRate,
        0.9,
        reason: '步进参数不随未选中预设的恢复变化',
      );
    });

    test('非法参数：忽略（预设与步进参数均不变）', () async {
      const invalid = SpeedStepParams(startRate: 1.0, maxRate: 0.5);
      await model().updatePreset(id: 'builtin_first', params: invalid);
      expect(
        doc().presets.firstWhere((p) => p.id == 'builtin_first').params,
        const SpeedStepParams(),
      );
    });
  });

  group('恢复默认', () {
    test('内置预设一键恢复出厂参数并落盘', () async {
      await model().updatePreset(
        id: 'builtin_first',
        params: const SpeedStepParams(
          startRate: 0.4,
          maxRate: 1.2,
          lapsPerRate: 4,
          rateIncrement: 0.2,
        ),
      );
      await model().restoreBuiltinDefault('builtin_first');

      final selected = doc().presets.firstWhere((p) => p.id == 'builtin_first');
      expect(selected.params, const SpeedStepParams());
      expect(container.read(speedControlProvider).stepParams,
          const SpeedStepParams());
      final saved = storage.snapshot['speedStepPresets']['presets'] as List;
      expect((saved[0]['params'] as Map)['startRate'], 0.5);
    });

    test('「复习」恢复默认回到新出厂值（0.5→1.0、每档 2 遍、+0.25）', () async {
      await model().select('builtin_review');
      await model().updatePreset(
        id: 'builtin_review',
        params: const SpeedStepParams(
          startRate: 0.8,
          maxRate: 1.2,
          lapsPerRate: 1,
          rateIncrement: 0.1,
        ),
      );

      await model().restoreBuiltinDefault('builtin_review');

      final review = doc().presets.firstWhere((p) => p.id == 'builtin_review');
      expect(
        review.params,
        const SpeedStepParams(
          startRate: 0.5,
          maxRate: 1.0,
          lapsPerRate: 2,
          rateIncrement: 0.25,
        ),
        reason: '恢复默认回到新出厂值',
      );
      expect(container.read(speedControlProvider).stepParams, review.params,
          reason: '选中预设恢复后步进参数随之应用');
    });
  });

  group('新建/删除自定义', () {
    test('新建：以当前选中预设参数为初值、自动选中、落盘', () async {
      await model().createCustom('我的节奏');

      expect(doc().presets.length, 3);
      expect(doc().selectedId, doc().presets.last.id);
      expect(doc().presets.last.builtin, isFalse);
      expect(doc().presets.last.name, '我的节奏');
      expect(doc().presets.last.params, const SpeedStepParams());
      expect(storage.snapshot['speedStepPresets']['presets'].length, 3);
    });

    test('空名不再静默无效——createCustom 空名兜底默认名「自定义 N」', () async {
      await model().createCustom('');
      expect(doc().presets.last.name, '自定义 1');

      // 连续空名新建：N 去重递增。
      await model().createCustom('   ');
      expect(doc().presets.last.name, '自定义 2');
    });

    test('默认名避开既有同名（改名后空名新建不冲突）', () async {
      await model().createCustom('自定义 1');
      await model().createCustom('');
      expect(doc().presets.last.name, '自定义 2');
    });

    test('删除选中的自定义：回退选中列表首个（内置）并应用其参数', () async {
      await model().createCustom('我的节奏');
      final customId = doc().selectedId;
      await model().updatePreset(
        id: customId,
        params: const SpeedStepParams(
          startRate: 0.3,
          maxRate: 0.9,
          lapsPerRate: 2,
          rateIncrement: 0.3,
        ),
      );

      await model().delete(customId);

      expect(doc().presets.length, 2);
      expect(
        doc().presets.where((p) => p.id == customId),
        isEmpty,
      );
      expect(doc().selectedId, 'builtin_first');
      expect(
        container.read(speedControlProvider).stepParams,
        const SpeedStepParams(),
      );
    });

    test('删除未选中的自定义：选中态不变', () async {
      await model().createCustom('A');
      final aId = doc().selectedId;
      await model().createCustom('B');
      expect(doc().selectedId, isNot(aId));

      await model().delete(aId);
      expect(doc().presets.length, 3);
      expect(doc().selectedId, isNot(aId));
    });
  });

  group('内置预设可删', () {
    test('删除未选中的内置：从列表消失并落盘', () async {
      await model().delete('builtin_review');

      expect(doc().presets.map((p) => p.id), ['builtin_first']);
      expect(doc().selectedId, 'builtin_first', reason: '选中未变');
      expect(
        (storage.snapshot['speedStepPresets']['presets'] as List).length,
        1,
        reason: '存储 schema 不变：数组里少一条即已删',
      );
    });

    test('删除选中的内置（选中但未启用）：回退选中列表首个并应用其参数', () async {
      await model().delete('builtin_first');

      expect(doc().presets.map((p) => p.id), ['builtin_review']);
      expect(doc().selectedId, 'builtin_review');
      expect(
        container.read(speedControlProvider).stepParams,
        const SpeedStepParams(
          startRate: 0.5,
          maxRate: 1.0,
          lapsPerRate: 2,
          rateIncrement: 0.25,
        ),
      );
    });

    test('删除正在生效的预设：步进一并停用、倍速回手动值', () async {
      await model().select('builtin_first');
      await container
          .read(speedControlProvider.notifier)
          .setStepEnabled(true);
      expect(engine.rate, 0.5, reason: '步进按该预设首档起跑');

      await model().delete('builtin_first');

      expect(container.read(speedControlProvider).stepEnabled, isFalse);
      expect(engine.rate, 1.0, reason: '停用后回到手动倍率');
      expect(doc().selectedId, 'builtin_review', reason: '回退选中列表首个');
    });

    test('录制期删除正在生效的预设：步进同样停用，且不写穿录制的 1.0×', () async {
      await model().select('builtin_first');
      await container
          .read(speedControlProvider.notifier)
          .setStepEnabled(true);
      container
          .read(compareRecordingPhaseProvider.notifier)
          .set(CompareRecordingPhase.recording);
      await engine.setRate(1.0); // 录制强制 1.0×。
      expect(container.read(speedControlProvider).stepEnabled, isTrue);

      await model().delete('builtin_first');

      expect(
        container.read(speedControlProvider).stepEnabled,
        isFalse,
        reason: '不留一条已删除的预设继续「生效」',
      );
      expect(engine.rate, 1.0, reason: '录制期不写穿引擎倍速');
      expect(doc().selectedId, 'builtin_review');
    });

    test('步进生效中删除未生效的那条预设：步进不受影响', () async {
      await model().select('builtin_first');
      await container
          .read(speedControlProvider.notifier)
          .setStepEnabled(true);

      await model().delete('builtin_review');

      expect(container.read(speedControlProvider).stepEnabled, isTrue);
      expect(engine.rate, 0.5);
      expect(doc().selectedId, 'builtin_first');
    });

    test('至少保留一条：剩余仅一条时删除被拒绝', () async {
      await model().delete('builtin_review');
      expect(doc().presets.length, 1);

      await model().delete('builtin_first');

      expect(doc().presets.length, 1, reason: '列表不会变成空');
      expect(doc().selectedId, 'builtin_first');
    });

    test('先新建一条自定义后可删光两条内置（列表仍有替代品）', () async {
      await model().createCustom('替代');
      final customId = doc().selectedId;

      await model().delete('builtin_first');
      await model().delete('builtin_review');

      expect(doc().presets.map((p) => p.id), [customId]);
      expect(doc().selectedId, customId);

      await model().delete(customId);
      expect(doc().presets.length, 1, reason: '最后一条仍删不掉');
    });

    test('跨会话：删除的内置不会随重启回来，schema 形状不变', () async {
      final first = makeContainer(restore: true);
      addTearDown(first.dispose);
      await first
          .read(speedStepPresetProvider.notifier)
          .delete('builtin_review');

      final second = makeContainer(restore: true);
      addTearDown(second.dispose);
      await Future<void>.delayed(Duration.zero);
      await second.read(speedStepPresetProvider.notifier).restoreDone;

      final restored = second.read(speedStepPresetProvider);
      expect(restored.presets.map((p) => p.id), ['builtin_first']);
      expect(restored.selectedId, 'builtin_first');
    });
  });

  group('重启等价（Testing Decisions）', () {
    test('重建 store（新容器 + 同一存储）后：预设内容与选中预设恢复；'
        '会话态（步进启用）不恢复', () async {
      final first = makeContainer(restore: true);
      addTearDown(first.dispose);
      await first
          .read(speedControlProvider.notifier)
          .setStepEnabled(true, scope: SpeedStepScope.wholeVideo);
      await first.read(speedStepPresetProvider.notifier).select('builtin_review');
      await first.read(speedStepPresetProvider.notifier).updatePreset(
            id: 'builtin_review',
            params: const SpeedStepParams(
              startRate: 0.8,
              maxRate: 1.4,
              lapsPerRate: 1,
              rateIncrement: 0.3,
            ),
          );
      await first.read(speedStepPresetProvider.notifier).createCustom('冲刺');
      first.dispose();

      // 「重启」：全新容器读取同一存储。
      final second = makeContainer(restore: true);
      addTearDown(second.dispose);
      // 等自动恢复完成。
      await Future<void>.delayed(Duration.zero);
      await second.read(speedStepPresetProvider.notifier).restoreDone;

      final doc = second.read(speedStepPresetProvider);
      expect(doc.presets.length, 3);
      final review =
          doc.presets.firstWhere((p) => p.id == 'builtin_review');
      expect(review.params.startRate, 0.8);
      expect(doc.presets.last.name, '冲刺');
      expect(doc.selectedId, doc.presets.last.id);
      expect(
        second.read(speedControlProvider).stepParams.startRate,
        0.8,
        reason: '选中预设参数随恢复应用',
      );
      // 会话态不落盘：步进启用为会话内 provider，重建后为停用。
      expect(second.read(speedControlProvider).stepEnabled, isFalse);
    });

    test('损坏但可解析的 JSON（字段类型错误）：回落到出厂内置预设', () async {
      await storage.write({
        'speedStepPresets': {
          'presets': [
            {
              'id': 'builtin_first',
              'name': '初见·大量练习',
              'builtin': true,
              'params': {'startRate': 'oops', 'maxRate': 1.0, 'lapsPerRate': 3, 'rateIncrement': 0.1},
            },
          ],
          'selectedId': 'builtin_first',
        },
      });
      final first = makeContainer(restore: true);
      addTearDown(first.dispose);
      await first.read(speedStepPresetProvider.notifier).restoreDone;

      final doc = first.read(speedStepPresetProvider);
      expect(doc.presets.map((p) => p.id),
          ['builtin_first', 'builtin_review']);
      expect(doc.selectedId, 'builtin_first');
    });

    test('存储为空/缺失（首次启动）：回落到出厂内置预设', () async {
      storage.reset();
      final first = makeContainer(restore: true);
      addTearDown(first.dispose);
      await first.read(speedStepPresetProvider.notifier).restoreDone;

      final doc = first.read(speedStepPresetProvider);
      expect(doc.presets.map((p) => p.id),
          ['builtin_first', 'builtin_review']);
      expect(doc.selectedId, 'builtin_first');
    });
  });

  group('同文件其它键保留', () {
    test('预设写盘只覆盖 speedStepPresets 键，并列键（avSyncDelays 等）保留',
        () async {
      storage.reset();
      // 并列键先在文件中（与生产同文件多键形态一致）。
      await storage.mutate((json, {required bool present}) async {
        json['avSyncDelays'] = {'其它设备': 60};
        json['metronomeSettings'] = {'soundType': 'ping'};
      });
      final first = makeContainer(restore: true);
      addTearDown(first.dispose);
      await first.read(speedStepPresetProvider.notifier).restoreDone;

      await model().select('builtin_review');

      final json = storage.snapshot;
      expect(json.containsKey('speedStepPresets'), isTrue);
      expect(json['avSyncDelays'], {'其它设备': 60});
      expect(json['metronomeSettings'], {'soundType': 'ping'});
    });
  });
}
