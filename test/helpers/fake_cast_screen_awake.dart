import 'package:dance_learning_app/cast/cast_screen_awake.dart';

/// 脚本化的假屏幕唤醒：记录**拿 / 放 / 再确认次数**（票 #39 的进出用例在它
/// 上面断言「进投屏态持有一次、离开释放一次」「画面开关在场时不重复持有」与
/// 「源画面件退场后再确认一次」）。照 `fake_system_mirror_launcher.dart` 的
/// 既有范式。
class FakeCastScreenAwake implements CastScreenAwake {
  FakeCastScreenAwake({this.onCall});

  /// 每次调用时的回调：顺序类用例把它接到**别的观测点**（画面件退场那一刻）
  /// 共用的一条时序表上，从而断言「谁在前、谁在后」。
  final void Function(String call)? onCall;

  /// 拿的次数（含重复持有）。
  int holdCalls = 0;

  /// 放的次数（含未持有时那次空放的调用）。
  int releaseCalls = 0;

  /// 再确认的次数（源画面件退场那一刻的补按；见 [CastScreenAwake.reassert]）。
  int reassertCalls = 0;

  /// 拿 / 放 / 再确认的调用序列，顺序类用例看它。
  final List<String> calls = [];

  /// 现在净持有几份（拿次数 − 放次数）；投屏期应当是 1。
  int get held => holdCalls - releaseCalls;

  @override
  Future<void> hold() async {
    holdCalls++;
    calls.add('hold');
    onCall?.call('hold');
  }

  @override
  Future<void> release() async {
    releaseCalls++;
    calls.add('release');
    onCall?.call('release');
  }

  @override
  Future<void> reassert() async {
    reassertCalls++;
    calls.add('reassert');
    onCall?.call('reassert');
  }
}
