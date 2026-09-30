import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatGridProvider, beatTrackStateProvider;
import 'package:dance_learning_app/core/atomic_json_file.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/persistence/prep_beats_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/in_memory_private_json_storage.dart';

/// 设备级「预备拍数」：真实文件 + 内存 fake 双跑
/// （先例：markers 持久化测试），缺省/非法回落、三项互不覆盖、与既有键
/// 共存、写回重读一致；模型层启动恢复 + 变更即落盘 + 重启等价。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('prep_beats_store');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  PrivateJsonStorage makeRealStorage() => AtomicJsonFile(
    File(p.join(tempDir.path, 'global_private.json')),
  );

  /// 磁盘原文（真实文件）/ 内存快照（fake）。
  Future<Map<String, dynamic>> readRaw(PrivateJsonStorage storage) async {
    if (storage is AtomicJsonFile) {
      final file = File(p.join(tempDir.path, 'global_private.json'));
      if (!await file.exists()) return {};
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
    return (storage as InMemoryPrivateJsonStorage).snapshot;
  }

  final tiers = {
    'delayedPlay': [2, 4, 8],
    'recording': [2, 4, 8],
    'loopLead': [0, 2, 4, 8],
  };

  /// 只读设备级设置（不触真实路径）：延迟循环档位派生自 prepBeats。
  ProviderContainer inMemoryContainer([List<Override> extra = const []]) =>
      ProviderContainer(
        overrides: [
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          ...extra,
        ],
      );

  group('PrepBeats 解码（缺省/非法逐字段回落默认 4/8/4）', () {
    test('键缺失 → 全默认', () {
      expect(PrepBeats.fromJson(null), const PrepBeats());
      expect(PrepBeats.fromJson('broken'), const PrepBeats());
      expect(PrepBeats.fromJson({}), const PrepBeats());
    });

    test('单项缺失/单项非法只影响自己，其余字段保留', () {
      final value = PrepBeats.fromJson({
        'delayedPlay': 8,
        'recording': 'bad',
        'loopLead': 0,
      });
      expect(value.delayedPlay, 8);
      expect(value.recording, 8);
      expect(value.loopLead, 0);
    });

    for (final entry in tiers.entries) {
      test('档位合法值全部接受：${entry.key}', () {
        for (final tier in entry.value) {
          final value = PrepBeats.fromJson({entry.key: tier});
          expect(switch (entry.key) {
            'delayedPlay' => value.delayedPlay,
            'recording' => value.recording,
            _ => value.loopLead,
          }, tier);
        }
      });
    }
  });

  for (final (label, makeStorage) in [
    ('真实文件', () => makeRealStorage()),
    ('内存 fake', () => InMemoryPrivateJsonStorage()),
  ]) {
    group('PrepBeatsStore（$label）', () {
      test('load：缺失兜底全默认', () async {
        expect(await PrepBeatsStore(makeStorage()).load(), const PrepBeats());
      });

      test('update：写入后重读一致；与既有设备级键互不覆盖', () async {
        final storage = makeStorage();
        await storage.mutate((json, {required bool present}) async => json['speedHistory'] = [1.5]);
        final store = PrepBeatsStore(storage);

        await store.update((current) => current.withFields(
              delayedPlay: 2,
              recording: 4,
              loopLead: 0,
            ));

        expect(await store.load(), const PrepBeats(
          delayedPlay: 2,
          recording: 4,
          loopLead: 0,
        ));
        expect((await readRaw(storage))['speedHistory'], [1.5]);

        // 再改一项：其余两项保持（三项互不覆盖）。
        await store.update((current) => current.withFields(recording: 8));
        expect(
          await store.load(),
          const PrepBeats(delayedPlay: 2, recording: 8, loopLead: 0),
        );
        expect((await readRaw(storage))['speedHistory'], [1.5]);
      });

      test('prepBeats 整体损坏 → 各项回落默认，不抛错', () async {
        final storage = makeStorage();
        await storage.mutate((json, {required bool present}) async => json['prepBeats'] = 42);
        expect(await PrepBeatsStore(storage).load(), const PrepBeats());
      });

      test('PrepBeatsModel：启动恢复 + 变更即落盘 + 重启等价', () async {
        final storage = makeStorage();
        await storage.mutate((json, {required bool present}) async => json['prepBeats'] = {
              'delayedPlay': 2,
              'recording': 8,
              'loopLead': 8,
            });

        Future<PrepBeats> openRead() async {
          final container = ProviderContainer(
            overrides: [
              privateJsonStorageProvider.overrideWithValue(storage),
            ],
          );
          addTearDown(container.dispose);
          await container.read(prepBeatsProvider.notifier).restoreDone;
          return container.read(prepBeatsProvider);
        }

        // 「重启」：新容器从存储恢复同一组值。
        expect(await openRead(),
            const PrepBeats(delayedPlay: 2, recording: 8, loopLead: 8));

        // 改值即落盘。
        final container = ProviderContainer(
          overrides: [
            privateJsonStorageProvider.overrideWithValue(storage),
          ],
        );
        addTearDown(container.dispose);
        container.read(prepBeatsProvider);
        await container.read(prepBeatsProvider.notifier).restoreDone;
        container.read(prepBeatsProvider.notifier).setDelayedPlay(8);
        await container.read(prepBeatsProvider.notifier).flushDone;

        expect(
          PrepBeats.fromJson((await readRaw(storage))['prepBeats']),
          const PrepBeats(delayedPlay: 8, recording: 8, loopLead: 8),
        );

        // 恢复竞态守卫：restore 未完成期间的改动不被启动恢复覆盖。
        expect(container.read(prepBeatsProvider).delayedPlay, 8);
      });

      test('启动恢复未完成时改动不冲掉另两项已存值；循环前导会话值自设备级恢复', () async {
        final storage = makeStorage();
        await storage.mutate(
          (json, {required bool present}) async => json['prepBeats'] = {'loopLead': 0},
        );
        final container = ProviderContainer(
          overrides: [
            privateJsonStorageProvider.overrideWithValue(storage),
          ],
        );
        addTearDown(container.dispose);
        container.listen(delayedLoopProvider, (_, _) {});
        await container.read(prepBeatsProvider.notifier).restoreDone;
        expect(container.read(delayedLoopProvider), DelayedLoopBeats.none);
      });

      test('启动恢复未完成时单项落盘只改目标字段（另两项已存值不被冲掉）', () async {
        final storage = makeStorage();
        await storage.mutate(
          (json, {required bool present}) async => json['prepBeats'] = {
            'delayedPlay': 2,
            'recording': 4,
            'loopLead': 8,
          },
        );
        final container = ProviderContainer(
          overrides: [
            privateJsonStorageProvider.overrideWithValue(storage),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(prepBeatsProvider.notifier)
            .setDelayedPlay(8); // 不等 restoreDone 即改。
        await container.read(prepBeatsProvider.notifier).flushDone;
        expect(
          PrepBeats.fromJson((await readRaw(storage))['prepBeats']),
          const PrepBeats(delayedPlay: 8, recording: 4, loopLead: 8),
        );
      });

      test('setLoopLead 后延迟循环档位派生同步', () async {
        final storage = makeStorage();
        final container = ProviderContainer(
          overrides: [
            privateJsonStorageProvider.overrideWithValue(storage),
          ],
        );
        addTearDown(container.dispose);
        container.listen(delayedLoopProvider, (_, _) {});
        container.read(prepBeatsProvider.notifier).setLoopLead(0);
        expect(container.read(delayedLoopProvider), DelayedLoopBeats.none);
      });
    });
  }

  group('延迟循环会话设置', () {
    test('默认 4 拍；选项 不延迟/2/4/8 可切换', () {
      final container = inMemoryContainer();
      addTearDown(container.dispose);

      expect(container.read(delayedLoopProvider), DelayedLoopBeats.four);

      container.read(prepBeatsProvider.notifier).setLoopLead(0);
      expect(container.read(delayedLoopProvider), DelayedLoopBeats.none);

      container.read(prepBeatsProvider.notifier).setLoopLead(2);
      expect(container.read(delayedLoopProvider), DelayedLoopBeats.two);

      container.read(prepBeatsProvider.notifier).setLoopLead(8);
      expect(container.read(delayedLoopProvider), DelayedLoopBeats.eight);
    });

    test('换算等待时长：拍时长 × 拍数（默认 BPM 120 → 每拍 0.5s）', () {
      final container = inMemoryContainer();
      addTearDown(container.dispose);

      container.read(prepBeatsProvider.notifier).setLoopLead(0);
      expect(container.read(delayedLoopWaitProvider), Duration.zero);

      container.read(prepBeatsProvider.notifier).setLoopLead(2);
      expect(
        container.read(delayedLoopWaitProvider),
        const Duration(seconds: 1),
      );

      container.read(prepBeatsProvider.notifier).setLoopLead(4);
      expect(
        container.read(delayedLoopWaitProvider),
        const Duration(seconds: 2),
      );

      container.read(prepBeatsProvider.notifier).setLoopLead(8);
      expect(
        container.read(delayedLoopWaitProvider),
        const Duration(seconds: 4),
      );
    });

    test('BPM 注入生效：120 → 60 时 4 拍等待翻倍', () {
      final container = inMemoryContainer([
        beatGridProvider.overrideWithValue(const UniformBeatGrid(bpm: 60)),
      ]);
      addTearDown(container.dispose);

      expect(
        container.read(delayedLoopWaitProvider),
        const Duration(seconds: 4),
      );
    });
  });

  group('节拍异常态秒制兜底', () {
    ProviderContainer errorStateContainer() {
      final container = inMemoryContainer([
        beatTrackStateProvider.overrideWithBuild(
          (ref, _) => const BeatTrackState.error(),
        ),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('延迟循环档位同数字秒：2→2s / 4→4s / 8→8s（拍制换算不走）', () {
      final container = errorStateContainer();

      container.read(prepBeatsProvider.notifier).setLoopLead(2);
      expect(
        container.read(delayedLoopWaitProvider),
        const Duration(seconds: 2),
      );

      container.read(prepBeatsProvider.notifier).setLoopLead(4);
      expect(
        container.read(delayedLoopWaitProvider),
        const Duration(seconds: 4),
      );

      container.read(prepBeatsProvider.notifier).setLoopLead(8);
      expect(
        container.read(delayedLoopWaitProvider),
        const Duration(seconds: 8),
      );

      // 「不延迟」档在异常态仍为零等待。
      container.read(prepBeatsProvider.notifier).setLoopLead(0);
      expect(container.read(delayedLoopWaitProvider), Duration.zero);
    });

    test('固定「一个八拍」等待兜底 4 秒：异常态网格每拍 0.5s（双指延迟播放/循环提示共享 seam）', () {
      final container = errorStateContainer();
      expect(
        container.read(beatGridProvider).eightBeatNominal,
        const Duration(seconds: 4),
      );
    });
  });
}
