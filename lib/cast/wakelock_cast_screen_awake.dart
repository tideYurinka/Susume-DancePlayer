/// 投屏期屏幕唤醒的**真实那一下**：`wakelock_plus` 的平台通道。
///
/// 它与播放内核画面件用的是**同一条**能力（media_kit_video 的 `Wakelock`
/// 就是调 `WakelockPlus`），所以「复用播放链路已有的唤醒能力」在这里是字面
/// 事实：投屏侧只是换了一个持有者，没有换一门平台能力，也没有引第二个包
/// ——`wakelock_plus` 本就在 lockfile 里（它是 media_kit_video 的传递依赖），
/// 这一票把它提升为直接依赖，与 `xml` 那次提升同款（见 `pubspec.yaml`）。
///
/// 失败一律**静默降级**（与画面件那份唤醒同款）：平台没有这门能力（非
/// Android 宿主、插件不在、通道报错）时投屏照旧——不因为一次拿不到唤醒把
/// 投屏挡下来，也不因为一次放不开把收尾挡住。
library;

import 'package:wakelock_plus/wakelock_plus.dart';

/// 真的落到平台的那一下：true = 持有唤醒（屏幕常亮），false = 放开（恢复
/// 系统行为）。异常吞掉——见库头。
Future<void> wakelockScreenAwakeToggle(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } on Object {
    // 平台没有这门能力：静默降级（投屏照旧）。
  }
}
