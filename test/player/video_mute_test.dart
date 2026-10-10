import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/beat_prompt_memory.dart'
    show beatPromptMemoryProvider;
import 'package:dance_learning_app/player/metronome_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 视频静音设置槽（面板「关闭视频声音」）：默认关；勾选即写播放内核
/// （mpv `mute`，只静这支视频、节拍声照旧）；会话值、不落盘。
void main() {
  late InMemoryPrivateJsonStorage storage;
  late FakePlaybackEngine engine;

  ProviderContainer makeContainer() {
    storage = InMemoryPrivateJsonStorage();
    engine = FakePlaybackEngine();
    final container = ProviderContainer(
      overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
        playbackEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('默认关：不勾选即视频有声音，未写过内核', () {
    final container = makeContainer();

    expect(container.read(videoMutedProvider), isFalse);
    expect(engine.videoMuteCalls, isEmpty);
  });

  test('勾选/取消即写内核：值跟着走、内核收到同值', () {
    final container = makeContainer();
    final model = container.read(videoMutedProvider.notifier);

    model.set(true);
    expect(container.read(videoMutedProvider), isTrue);
    expect(engine.videoMuteCalls, [true]);

    model.set(false);
    expect(container.read(videoMutedProvider), isFalse);
    expect(engine.videoMuteCalls, [true, false]);
  });

  test('不落盘：勾选既不写设备级设置、也不写这支舞的节拍提示记忆', () async {
    final container = makeContainer();

    container.read(videoMutedProvider.notifier).set(true);
    await pumpEventQueue();

    expect(storage.snapshot, isEmpty);
    expect(container.read(beatPromptMemoryProvider), isNull);
  });

  test('关掉「声音反馈」总开关：视频静音一并解除，不留全静音', () {
    final container = makeContainer();
    container.read(metronomeSoundEnabledProvider.notifier).set(true);
    container.read(videoMutedProvider.notifier).set(true);

    container.read(metronomeSoundEnabledProvider.notifier).set(false);

    expect(container.read(videoMutedProvider), isFalse);
    expect(engine.videoMuteCalls.last, isFalse);
  });

  test('会话复位：值回有声音，内核无条件写回不静音', () {
    final container = makeContainer();
    final model = container.read(videoMutedProvider.notifier);

    model.set(true);
    model.reset();
    expect(container.read(videoMutedProvider), isFalse);
    expect(engine.videoMuteCalls, [true, false]);

    // 值本就是 false（未经用户勾选的那一次打开）同样写回：内核的静音
    // 属性不随视频切换自己消失。
    model.reset();
    expect(engine.videoMuteCalls, [true, false, false]);
  });
}
