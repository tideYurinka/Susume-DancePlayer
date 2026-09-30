import 'package:dance_learning_app/player/beat_schedule.dart';

/// 假排程消费者（seam 注入）：记录决策层产出的排程指令与
/// flush 调用，断言「哪拍、何时、哪段、多大音量」。
class FakeBeatScheduleConsumer implements BeatScheduleConsumer {
  final List<BeatScheduleCommand> commands = [];
  int flushCount = 0;

  @override
  Future<bool> schedule(BeatScheduleCommand command) async {
    commands.add(command);
    return true;
  }

  @override
  Future<void> flush() async {
    flushCount++;
  }
}
