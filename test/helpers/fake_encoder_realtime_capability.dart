import 'package:dance_learning_app/cast/cast_encoder_realtime.dart';
import 'package:dance_learning_app/cast/encoder_realtime_capability.dart';

/// 脚本化的假**编码器 1× 实时能力查询**：给出三态中的任一个——或让查询自己
/// 炸掉（[failure]），用来验调用方「问不到 = 按不可保证处理」的那条兜底。
/// 照 `fake_system_mirror_launcher.dart` 的既有范式。
class FakeEncoderRealtimeCapability implements CastEncoderRealtimeCapability {
  FakeEncoderRealtimeCapability({
    this.answer = CastEncoderRealtime.guaranteed,
  });

  /// 查询给的答案。
  CastEncoderRealtime answer;

  /// 非 null 时 [query] 抛它（模拟查询本身失败：调用方要按「问不到」兜底，
  /// 而不是把整块面板带崩）。
  Object? failure;

  /// [query] 的调用次数。
  int queryCalls = 0;

  /// 每次询问传进来的**目标尺寸**（调用方问的是哪一档）。
  final List<CastEncoderQueryTarget> queriedTargets = [];

  @override
  Future<CastEncoderRealtime> query(CastEncoderQueryTarget target) async {
    queryCalls++;
    queriedTargets.add(target);
    final failure = this.failure;
    if (failure != null) throw failure;
    return answer;
  }
}
