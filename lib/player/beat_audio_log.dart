import 'package:flutter/foundation.dart' show debugPrint;

/// 节拍声生命周期诊断日志 tag（单 tag）：真机 logcat 按此过滤——
/// 开流失败（含原因）、流被系统错误关闭与重开、哑 sink（原生库不可用）。
///
/// 沿用本仓既有诊断日志纪律（先例 `lib/player/loop_prompt.dart` 的越尾线
/// 加固日志）：**单 tag + 统一输出函数 + 单一出口**，测试注入捕获
/// `debugPrint` 断言内容——不新开第二套机制，也不加常驻诊断 UI。
const String kBeatAudioLogTag = '[beatAudio]';

/// 统一诊断输出：发声链失败可见的**唯一出口**。
void beatAudioLog(String message) {
  debugPrint('$kBeatAudioLogTag $message');
}
