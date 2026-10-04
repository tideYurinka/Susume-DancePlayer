import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/persistence/local_document.dart'
    show BeatPromptMemoryFields;
import 'package:dance_learning_app/player/beat_animation.dart';
import 'package:dance_learning_app/player/beat_prompt_memory.dart';
import 'package:dance_learning_app/player/beat_prompt_panel.dart'
    show beatPromptEnabledProvider;
import 'package:dance_learning_app/player/metronome_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_private_json_storage.dart';

/// 生效值与设备默认：五个值各有一个生效值——
/// 记忆有值用记忆值，缺席按字段默认（总开关恒关、形态/音源/半拍取设备级
/// 「新舞默认」）；用户设置动作经设置槽写入口双写记忆与设备级字段，总开关
/// 只写记忆。只断言外部可观测行为：生效值读数与 `metronomeSettings` 文件
/// 内容（内存私密 JSON）。
void main() {
  late InMemoryPrivateJsonStorage storage;

  ProviderContainer makeContainer({Map<String, dynamic> initial = const {}}) {
    storage = InMemoryPrivateJsonStorage(initial: initial);
    final container = ProviderContainer(
      overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 设备级「新舞默认」三槽的启动恢复完成。
  Future<void> deviceRestored(ProviderContainer container) async {
    await container
        .read(beatAnimationStyleDefaultProvider.notifier)
        .restoreDone;
    await container
        .read(metronomeSoundTypeDefaultProvider.notifier)
        .restoreDone;
    await container
        .read(metronomeHalfBeatEnabledDefaultProvider.notifier)
        .restoreDone;
  }

  test('记忆缺席：总开关读关，形态/音源/半拍读设备级当前值', () async {
    final container = makeContainer(
      initial: {
        'metronomeSettings': {
          'animationStyle': 'pendulum',
          'halfBeatEnabled': false,
        },
      },
    );
    await deviceRestored(container);

    expect(container.read(beatPromptEnabledProvider), isFalse);
    expect(container.read(metronomeSoundEnabledProvider), isFalse);
    expect(
      container.read(beatAnimationStyleProvider),
      BeatAnimationStyle.pendulum,
    );
    expect(
      container.read(metronomeSoundTypeProvider),
      MetronomeSoundType.normal,
    );
    expect(container.read(metronomeHalfBeatEnabledProvider), isFalse);
  });

  test('记忆有值：生效值取记忆值，设备级那一层不再影响这一支舞', () async {
    final container = makeContainer();
    await deviceRestored(container);
    container.read(beatPromptMemoryProvider.notifier).setAnimation(true);
    container
        .read(beatPromptMemoryProvider.notifier)
        .setAnimationStyle('pendulum');
    container.read(beatPromptMemoryProvider.notifier).setSoundType('normal');
    container.read(beatPromptMemoryProvider.notifier).setHalfBeat(false);

    // 设备级那一层被另行改动（另一支舞的用户动作）：本支舞不受影响。
    container
        .read(beatAnimationStyleDefaultProvider.notifier)
        .set(BeatAnimationStyle.bar);
    container.read(metronomeHalfBeatEnabledDefaultProvider.notifier).set(true);
    await container.read(beatAnimationStyleDefaultProvider.notifier).flushDone;

    expect(container.read(beatPromptEnabledProvider), isTrue);
    expect(
      container.read(beatAnimationStyleProvider),
      BeatAnimationStyle.pendulum,
    );
    expect(container.read(metronomeHalfBeatEnabledProvider), isFalse);
  });

  test('记忆缺席舞上改形态/音源/半拍：生效值立刻变，设备级同时写成同一个值', () async {
    final container = makeContainer();
    await deviceRestored(container);

    // 内存存储按「单次 update」收口、不串行化并发写，逐字段顺序等落盘
    // 完成再改下一字段（真实 AtomicJsonFile.update 本身串行）。
    container
        .read(beatAnimationStyleProvider.notifier)
        .set(BeatAnimationStyle.pendulum);
    await container.read(beatAnimationStyleDefaultProvider.notifier).flushDone;
    container
        .read(metronomeSoundTypeProvider.notifier)
        .set(MetronomeSoundType.vocal);
    await container.read(metronomeSoundTypeDefaultProvider.notifier).flushDone;
    container.read(metronomeHalfBeatEnabledProvider.notifier).set(false);
    await container
        .read(metronomeHalfBeatEnabledDefaultProvider.notifier)
        .flushDone;

    expect(
      container.read(beatAnimationStyleProvider),
      BeatAnimationStyle.pendulum,
    );
    expect(
      container.read(metronomeSoundTypeProvider),
      MetronomeSoundType.vocal,
    );
    expect(container.read(metronomeHalfBeatEnabledProvider), isFalse);
    expect(storage.snapshot['metronomeSettings'], {
      'animationStyle': 'pendulum',
      'soundType': 'vocal',
      'halfBeatEnabled': false,
    });
  });

  test('改完之后：新的一支无记忆舞按新设备级值生效；有记忆的舞保持自己的记忆值', () async {
    final first = makeContainer();
    await deviceRestored(first);
    // 第一支舞：改了形态，也带着自己的记忆值（半拍关）。
    first.read(beatPromptMemoryProvider.notifier).setHalfBeat(false);
    first
        .read(beatAnimationStyleProvider.notifier)
        .set(BeatAnimationStyle.pendulum);
    await first.read(beatAnimationStyleDefaultProvider.notifier).flushDone;
    first.dispose();

    // 下一支无记忆的新舞（同设备）：按新的设备级默认生效。
    final nextStorage = storage;
    final next = ProviderContainer(
      overrides: [privateJsonStorageProvider.overrideWithValue(nextStorage)],
    );
    addTearDown(next.dispose);
    await next.read(beatAnimationStyleDefaultProvider.notifier).restoreDone;
    await next
        .read(metronomeHalfBeatEnabledDefaultProvider.notifier)
        .restoreDone;
    expect(next.read(beatAnimationStyleProvider), BeatAnimationStyle.pendulum);
    expect(next.read(metronomeHalfBeatEnabledProvider), isTrue);

    // 另一支有记忆的舞：半拍保持自己的记忆值（关），不被新默认翻掉。
    // （音源记忆值受归一口径约束、只有「普通」可解码，与设备默认
    // 无法构成可观测的分歧，故本支舞的记忆独立性用半拍声断言。）
    next.read(beatPromptMemoryProvider.notifier).setHalfBeat(false);
    next.read(metronomeHalfBeatEnabledDefaultProvider.notifier).set(true);
    expect(next.read(metronomeHalfBeatEnabledProvider), isFalse);
  });

  test('记忆缺席舞上重选同值也是一次表态：记忆字段照落（否则仍是「无记录」）', () async {
    final container = makeContainer();
    await deviceRestored(container);
    expect(container.read(beatPromptMemoryProvider), isNull);

    // 设备默认已是 pendulum，用户仍显式重选 pendulum。
    container
        .read(beatAnimationStyleProvider.notifier)
        .set(BeatAnimationStyle.pendulum);
    expect(
      container.read(beatAnimationStyleProvider),
      BeatAnimationStyle.pendulum,
    );
    expect(
      container.read(beatPromptMemoryProvider)?.animationStyle,
      'pendulum',
    );
  });

  test('改两个总开关：只写记忆，设备级任何字段都不被触碰', () async {
    final container = makeContainer();
    await deviceRestored(container);
    final before = Map<String, dynamic>.of(storage.snapshot);

    container.read(beatPromptEnabledProvider.notifier).set(true);
    container.read(metronomeSoundEnabledProvider.notifier).set(true);
    await pumpEventQueue();

    expect(container.read(beatPromptEnabledProvider), isTrue);
    expect(container.read(metronomeSoundEnabledProvider), isTrue);
    expect(storage.snapshot, before);
    expect(
      container.read(beatPromptMemoryProvider),
      const BeatPromptMemoryFields(animation: true, sound: true),
    );
  });
}
