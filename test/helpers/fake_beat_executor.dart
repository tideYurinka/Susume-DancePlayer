import 'package:dance_learning_app/player/beat_schedule.dart';

/// 假节拍执行器（seam 注入）：[BeatScheduleConsumer] 与 [BeatStreamControl]
/// 同一实例——记录开/停/清流调用与全部排程指令，并带一个可控单调钟。
/// 节拍呈现的对象装配缝与驱动缝共用（同一 fake 同时回答消费面与流面）。
class FakeBeatExecutor implements BeatScheduleConsumer, BeatStreamControl {
  int openCount = 0;
  int stopCount = 0;
  int flushCount = 0;

  /// 可控单调钟（毫秒）。
  int nowMs = 0;

  /// 流已被系统错误关闭（失效探测路径）。
  bool lost = false;

  /// 开流失败（自愈路径）。
  bool failOpens = false;

  final List<BeatScheduleCommand> commands = [];

  @override
  Future<bool> schedule(BeatScheduleCommand command) async {
    commands.add(command);
    return true;
  }

  @override
  Future<void> flush() async {
    flushCount++;
  }

  @override
  bool streamLost() => lost;

  @override
  Future<void> openStream() async {
    if (failOpens) throw Exception('开流失败（fake）');
    openCount++;
  }

  @override
  void stopStream() {
    stopCount++;
  }

  @override
  Future<void> rebuildTransport() async {}

  @override
  int monotonicMs() => nowMs;
}
