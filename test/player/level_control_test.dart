import 'dart:async';

import 'package:dance_learning_app/player/brightness.dart';
import 'package:dance_learning_app/player/level_control.dart';
import 'package:dance_learning_app/player/system_volume.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_brightness.dart';
import '../helpers/fake_system_volume.dart';

/// 亮度/音量域直测：不 pump widget、不注容器。
///
/// seam = 两个接缝接口（假件记录调用）＋域自身交出的取值；断言只看
/// 「基线从哪来」「增量写到哪」「收尾后还跟不跟随」。
void main() {
  late FakeScreenBrightnessController brightness;
  late FakeSystemMediaVolumeController volume;
  late LevelControl level;

  setUp(() {
    brightness = FakeScreenBrightnessController(initialBrightness: 0.4);
    volume = FakeSystemMediaVolumeController(currentVolume: 0.4);
    level = LevelControl(
      brightnessController: brightness,
      volumeController: volume,
    );
  });

  tearDown(() => level.dispose());

  Future<void> start() async {
    level.start();
    await Future<void>.delayed(Duration.zero);
  }

  /// 让域排队的写回微任务跑到（写入排在反馈呈现之后）。
  Future<void> flushWrites() => Future<void>.delayed(Duration.zero);

  group('初始化基线', () {
    test('系统媒体音量基线：调节从系统现值起算（引擎零参与）', () async {
      await start();

      expect(level.volume, closeTo(0.4, 1e-9));
      final value = level.adjustVolume(deltaPx: -100, areaHeight: 1000);

      expect(value, closeTo(0.3, 1e-9));
      await flushWrites();
      expect(volume.currentVolume, closeTo(0.3, 1e-9));
      expect(volume.setCalls.single, closeTo(0.3, 1e-9));
    });

    test('应用亮度基线：调节从应用现值起算', () async {
      await start();

      expect(level.brightness, closeTo(0.4, 1e-9));
      final value = level.adjustBrightness(deltaPx: 100, areaHeight: 1000);

      expect(value, closeTo(0.5, 1e-9));
      await flushWrites();
      expect(brightness.setCalls.single, closeTo(0.5, 1e-9));
    });

    test('基线读取失败保持默认、不抛错', () async {
      final failing = _FailingBrightnessController();
      final subject = LevelControl(
        brightnessController: failing,
        volumeController: volume,
      );
      addTearDown(subject.dispose);

      subject.start();
      await Future<void>.delayed(Duration.zero);

      expect(subject.brightness, 1.0);
      expect(subject.adjustBrightness(deltaPx: 100, areaHeight: 1000), 1.0);
    });
  });

  group('写入路径', () {
    test('纵向增量按作用区高度归一化并钳在 0..1：越界写端到端同值', () async {
      await start();

      expect(level.adjustVolume(deltaPx: -9999, areaHeight: 1000), 0.0);
      expect(level.adjustVolume(deltaPx: 9999, areaHeight: 1000), 1.0);
      await flushWrites();

      expect(volume.setCalls, [0.0, 1.0]);
    });

    test('音量写入失败静默：取值照常更新、不抛错', () async {
      final failing = _FailingVolumeController(currentVolume: 0.5);
      final subject = LevelControl(
        brightnessController: brightness,
        volumeController: failing,
      );
      addTearDown(subject.dispose);
      subject.start();
      await Future<void>.delayed(Duration.zero);

      expect(
        subject.adjustVolume(deltaPx: 100, areaHeight: 1000),
        closeTo(0.6, 1e-9),
      );
      await flushWrites(); // 写失败在域内被吞
    });
  });

  group('手势会话回滚', () {
    test('取消收尾：音量写回首次调节动作时的快照', () async {
      await start();
      level.adjustVolume(deltaPx: 200, areaHeight: 1000);
      level.adjustVolume(deltaPx: 200, areaHeight: 1000);
      await flushWrites();
      expect(volume.setCalls, [closeTo(0.6, 1e-9), closeTo(0.8, 1e-9)]);

      level.endGestureSession(cancel: true);
      await flushWrites();

      expect(volume.setCalls.last, closeTo(0.4, 1e-9), reason: '写回起手值');
      expect(level.volume, closeTo(0.4, 1e-9));
    });

    test('取消收尾：亮度写回首次调节动作时的快照', () async {
      await start();
      level.adjustBrightness(deltaPx: -300, areaHeight: 1000);
      await flushWrites();

      level.endGestureSession(cancel: true);
      await flushWrites();

      expect(brightness.setCalls, [closeTo(0.1, 1e-9), closeTo(0.4, 1e-9)]);
      expect(level.brightness, closeTo(0.4, 1e-9));
    });

    test('未产生调节动作的会话收尾无写', () async {
      await start();
      level.endGestureSession(cancel: true);
      await flushWrites();

      expect(volume.setCalls, isEmpty);
      expect(brightness.setCalls, isEmpty);
    });

    test('非取消收尾不写回：新值保留', () async {
      await start();
      level.adjustBrightness(deltaPx: 100, areaHeight: 1000);
      await flushWrites();

      level.endGestureSession(cancel: false);
      await flushWrites();

      expect(brightness.setCalls, [closeTo(0.5, 1e-9)]);
      expect(level.brightness, closeTo(0.5, 1e-9));
    });

    test('值未变化不重复写', () async {
      await start();
      level.adjustVolume(deltaPx: 100, areaHeight: 1000);
      level.adjustVolume(deltaPx: -100, areaHeight: 1000);
      await flushWrites();
      expect(volume.setCalls, hasLength(2));

      level.endGestureSession(cancel: true);
      await flushWrites();

      expect(volume.setCalls, hasLength(2), reason: '写回值与现值相同不重复写');
    });

    test('重复收尾幂等', () async {
      await start();
      level.adjustVolume(deltaPx: 200, areaHeight: 1000);
      await flushWrites();
      level.endGestureSession(cancel: true);
      await flushWrites();
      final calls = List<double>.of(volume.setCalls);

      level.endGestureSession(cancel: true);
      await flushWrites();

      expect(volume.setCalls, calls);
    });
  });

  group('应用外音量变化', () {
    test('侧键等经 volumeStream 同步基线：此后调节从新值起算', () async {
      await start();

      volume.emitExternal(0.2);
      await Future<void>.delayed(Duration.zero);

      expect(level.volume, closeTo(0.2, 1e-9));
      expect(
        level.adjustVolume(deltaPx: 50, areaHeight: 1000),
        closeTo(0.25, 1e-9),
      );
    });

    test('外部事件先于基线读取返回时让位：不被陈旧读取覆盖', () async {
      final slow = _SlowVolumeController();
      final subject = LevelControl(
        brightnessController: brightness,
        volumeController: slow,
      );
      addTearDown(subject.dispose);

      subject.start();
      slow.emitExternal(0.2); // 读取尚未返回
      slow.completeRead(0.9); // 陈旧基线晚到
      await Future<void>.delayed(Duration.zero);

      expect(subject.volume, closeTo(0.2, 1e-9));
    });

    test('dispose 后不再跟随应用外变化', () async {
      await start();
      level.dispose();

      volume.emitExternal(0.2);
      await Future<void>.delayed(Duration.zero);

      expect(level.volume, closeTo(0.4, 1e-9));
    });

    test('收尾后晚到的基线读取不再写取值（老页面 mounted 门）', () async {
      final slow = _SlowVolumeController();
      final subject = LevelControl(
        brightnessController: brightness,
        volumeController: slow,
      );
      addTearDown(subject.dispose);

      subject.start();
      subject.dispose();
      slow.completeRead(0.9);
      await Future<void>.delayed(Duration.zero);

      expect(subject.volume, 1.0);
    });
  });
}

/// 读取/写入都抛错的亮度件：断言基线读取兜底（既有「不阻塞播放」口径）。
class _FailingBrightnessController implements ScreenBrightnessController {
  @override
  Future<double> get brightness => Future<double>.error(StateError('不可用'));

  @override
  Future<void> setBrightness(double value) async {}
}

/// 写入抛错的音量件：断言音量写入口吞错（与真实平台通道未注册同口径）。
class _FailingVolumeController extends FakeSystemMediaVolumeController {
  _FailingVolumeController({super.currentVolume});

  @override
  Future<void> setVolume(double value) async {
    throw StateError('平台通道未注册');
  }
}

/// 读取由测试手动完成的音量件：制造「外部事件先于基线读取返回」的竞态。
class _SlowVolumeController implements SystemMediaVolumeController {
  final Completer<double> _read = Completer<double>();
  final StreamController<double> _changes =
      StreamController<double>.broadcast();

  void completeRead(double value) => _read.complete(value);

  void emitExternal(double value) => _changes.add(value);

  @override
  Future<double> get volume => _read.future;

  @override
  Future<void> setVolume(double value) async {}

  @override
  Stream<double> get volumeStream => _changes.stream;
}
