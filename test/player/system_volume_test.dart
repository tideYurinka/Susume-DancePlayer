import 'package:dance_learning_app/player/system_volume.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 平台通道 mock 回包：get → 当前 {volume, max} 刻度值。
  void mockGet(int volume, int max) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dance_learning_app/system_media_volume'),
          (call) async => switch (call.method) {
            'get' => {'volume': volume, 'max': max},
            _ => null,
          },
        );
  }

  /// set 调用记录（断言钳制后写入平台的归一化值）。
  final setArgs = <double>[];

  tearDown(() {
    setArgs.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dance_learning_app/system_media_volume'),
          null,
        );
  });

  group('PlatformSystemMediaVolumeController（平台通道 seam）', () {
    test('get：按平台当前刻度/最大刻度归一化为 0..1', () async {
      mockGet(6, 10);
      final controller = PlatformSystemMediaVolumeController();
      expect(await controller.volume, closeTo(0.6, 1e-9));
    });

    test('get：最大刻度 0（异常平台）回落 0.0 不除零', () async {
      mockGet(0, 0);
      final controller = PlatformSystemMediaVolumeController();
      expect(await controller.volume, 0.0);
    });

    test('set：越界钳制到 0..1 后写入平台', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dance_learning_app/system_media_volume'),
            (call) async {
              if (call.method == 'set') {
                setArgs.add(call.arguments['volume'] as double);
              }
              return null;
            },
          );
      final controller = PlatformSystemMediaVolumeController();
      await controller.setVolume(1.5);
      await controller.setVolume(-0.2);
      await controller.setVolume(0.4);
      expect(setArgs, [1.0, 0.0, 0.4]);
    });

    test('volumeStream：事件刻度值归一化为 0..1', () async {
      final controller = PlatformSystemMediaVolumeController();
      final events = controller.volumeStream;
      final received = <double>[];
      final subscription = events.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'dance_learning_app/system_media_volume_events',
            const StandardMethodCodec().encodeSuccessEnvelope({
              'volume': 3,
              'max': 10,
            }),
            (_) {},
          );
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(received.single, closeTo(0.3, 1e-9));
    });
  });
}
