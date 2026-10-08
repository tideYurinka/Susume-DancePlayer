import 'dart:io';

import 'package:dance_learning_app/cast/cast_encoder_realtime.dart';
import 'package:dance_learning_app/cast/encoder_realtime_capability.dart';
import 'package:dance_learning_app/cast/platform_encoder_realtime_capability.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_encoder_realtime_capability.dart';

/// 编码器能力查询的真实实现直测：经 test messenger 模拟原生侧，钉住**三态**
/// ——`guaranteed` / `notGuaranteed` 两条线值原样过桥，其余（null、认不得的
/// 字、通道不在、原生报错、API < 29 那一侧）**一律问不到**（unknown），
/// 绝不退化成「保证」。
///
/// 原生侧在真机上读不读得出性能点（`getSupportedPerformancePoints` 在
/// Android 10+ 的行为、硬编优先挑得对不对）留真机验收——步骤见
/// `lib/cast/docs/real-device-acceptance.md`；通道的两条线值在下面按**声明的
/// 事实**（Kotlin 文件正文）对齐。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kCastEncoderRealtimeChannelName);

  late List<String> asked;
  late Object? answer;
  late Object? thrown;

  void installMock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          asked.add(call.method);
          if (thrown != null) throw thrown!;
          return answer;
        });
  }

  setUp(() {
    asked = [];
    answer = null;
    thrown = null;
    installMock();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const queryMethod = kCastEncoderRealtimeMethod;

  test('保证 1× 实时：原样过桥（不降级那一态）', () async {
    answer = kCastEncoderRealtimeGuaranteedAnswer;

    expect(
      await PlatformEncoderRealtimeCapability().query(),
      CastEncoderRealtime.guaranteed,
    );
    expect(asked, [queryMethod]);
  });

  test('不保证 1× 实时：原样过桥（降级那一态）', () async {
    answer = kCastEncoderRealtimeNotGuaranteedAnswer;

    expect(
      await PlatformEncoderRealtimeCapability().query(),
      CastEncoderRealtime.notGuaranteed,
    );
  });

  test('原生明说问不到（API < 29）：过桥成 unknown，不压成 false', () async {
    answer = kCastEncoderRealtimeUnknownAnswer;

    expect(
      await PlatformEncoderRealtimeCapability().query(),
      CastEncoderRealtime.unknown,
    );
  });

  test('原生没返回值（null）：按问不到处理，不退化成「保证」', () async {
    answer = null;

    expect(
      await PlatformEncoderRealtimeCapability().query(),
      CastEncoderRealtime.unknown,
    );
  });

  test('认不得的答案：按问不到处理', () {
    expect(
      castEncoderRealtimeFromWire('yes'),
      CastEncoderRealtime.unknown,
    );
    expect(castEncoderRealtimeFromWire(1), CastEncoderRealtime.unknown);
    expect(
      castEncoderRealtimeFromWire(kCastEncoderRealtimeGuaranteedAnswer),
      CastEncoderRealtime.guaranteed,
    );
    expect(
      castEncoderRealtimeFromWire(kCastEncoderRealtimeNotGuaranteedAnswer),
      CastEncoderRealtime.notGuaranteed,
    );
  });

  test('原生这边报错：按问不到处理，不向上抛', () async {
    thrown = PlatformException(code: 'no_codec');

    expect(
      await PlatformEncoderRealtimeCapability().query(),
      CastEncoderRealtime.unknown,
    );
  });

  test('通道不在（非 Android 宿主 / 插件未注册）：按问不到处理，不向上抛', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    expect(
      await PlatformEncoderRealtimeCapability().query(),
      CastEncoderRealtime.unknown,
    );
  });

  test('通道在但没这条方法（notImplemented）：按问不到处理', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          asked.add(call.method);
          return null;
        });

    expect(
      await PlatformEncoderRealtimeCapability().query(),
      CastEncoderRealtime.unknown,
    );
    expect(asked, [queryMethod]);
  });

  test('缺省装配走真实实现；测试可注入替身', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(castEncoderRealtimeCapabilityProvider),
      isA<PlatformEncoderRealtimeCapability>(),
    );

    final fake = FakeEncoderRealtimeCapability(
      answer: CastEncoderRealtime.notGuaranteed,
    );
    final injected = ProviderContainer(
      overrides: [
        castEncoderRealtimeCapabilityProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(injected.dispose);

    expect(
      await injected.read(castEncoderRealtimeCapabilityProvider).query(),
      CastEncoderRealtime.notGuaranteed,
    );
    expect(fake.queryCalls, 1);
  });

  test('原生一半的声明事实：通道名、方法名与两条线值逐字对齐', () {
    final source = File(
      'android/app/src/main/kotlin/top/yurinka/susume/'
      'EncoderRealtimeCapabilityPlugin.kt',
    ).readAsStringSync();

    expect(source, contains('"$kCastEncoderRealtimeChannelName"'));
    expect(source, contains('"$kCastEncoderRealtimeMethod"'));
    expect(source, contains('"$kCastEncoderRealtimeGuaranteedAnswer"'));
    expect(source, contains('"$kCastEncoderRealtimeNotGuaranteedAnswer"'));
    expect(source, contains('"$kCastEncoderRealtimeUnknownAnswer"'));
    // 性能点是 API 29（Android 10）才有的：API < 29 那一侧必须明说问不到。
    expect(source, contains('Build.VERSION_CODES.Q'));
  });
}
