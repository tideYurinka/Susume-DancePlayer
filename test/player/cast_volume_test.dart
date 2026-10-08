import 'package:dance_learning_app/player/cast_volume.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_system_volume.dart';

/// 投屏期音量接缝直测（票 #38）：**写入路径按会话模式分派**——非投屏走本机
/// 系统媒体音量、投屏走接收端（读上报值 / 写 SetVolume）。不启动 widget、不
/// 碰网络：接收端侧经 [CastVolume] 的替身记录调用。
class _FakeCastVolume implements CastVolume {
  final List<double> writes = [];
  int reads = 0;
  double reported = 0.5;

  /// 非 null 时 [reportedVolume] 返回 null（设备不报 / 没端点）。
  bool unreadable = false;

  @override
  Future<void> setVolume(double volume) async => writes.add(volume);

  @override
  Future<double?> reportedVolume() async {
    reads++;
    return unreadable ? null : reported;
  }
}

void main() {
  late FakeSystemMediaVolumeController local;
  late _FakeCastVolume cast;
  late bool casting;
  late CastAwareSystemMediaVolumeController controller;

  setUp(() {
    local = FakeSystemMediaVolumeController(currentVolume: 0.9);
    cast = _FakeCastVolume();
    casting = false;
    controller = CastAwareSystemMediaVolumeController(
      local: local,
      isCasting: () => casting,
      cast: cast,
    );
  });

  test('非投屏：读写本机系统媒体音量，接收端一次都不碰（行为逐位不变）', () async {
    expect(await controller.volume, closeTo(0.9, 1e-9));
    await controller.setVolume(0.3);

    expect(local.currentVolume, closeTo(0.3, 1e-9));
    expect(local.setCalls, [closeTo(0.3, 1e-9)]);
    expect(cast.reads, 0);
    expect(cast.writes, isEmpty);
  });

  test('投屏：读的是接收端上报值、写的是接收端 SetVolume，本机音量一位不动', () async {
    casting = true;
    cast.reported = 0.4;

    expect(await controller.volume, closeTo(0.4, 1e-9));
    await controller.setVolume(0.6);

    expect(cast.reads, 1);
    expect(cast.writes, [closeTo(0.6, 1e-9)]);
    expect(local.setCalls, isEmpty, reason: '投屏期手机是遥控器，声音归电视');
    expect(local.currentVolume, closeTo(0.9, 1e-9));
  });

  test('投屏且接收端不报音量：读取抛错（界面保持现值，不显示 0）', () async {
    casting = true;
    cast.unreadable = true;

    await expectLater(controller.volume, throwsA(isA<StateError>()));
  });

  test('写入越界值：钳到 0..1 再交给接收端', () async {
    casting = true;
    await controller.setVolume(1.4);
    await controller.setVolume(-0.2);
    expect(cast.writes, [1.0, 0.0]);
  });

  test('音量变化流：非投屏透传本机事件；投屏期本机事件不覆盖接收端读数', () async {
    final seen = <double>[];
    final subscription = controller.volumeStream.listen(seen.add);
    addTearDown(subscription.cancel);

    local.emitExternal(0.8);
    await pumpEventQueue();
    expect(seen, [closeTo(0.8, 1e-9)], reason: '非投屏照旧跟随侧键等来源');

    casting = true;
    local.emitExternal(0.2);
    await pumpEventQueue();
    expect(seen, hasLength(1), reason: '投屏期本机音量事件不覆盖屏上的接收端读数');

    casting = false;
    local.emitExternal(0.55);
    await pumpEventQueue();
    expect(seen.last, closeTo(0.55, 1e-9));
  });
}
