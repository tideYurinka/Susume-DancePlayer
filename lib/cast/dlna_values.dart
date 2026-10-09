/// DLNA 应答里**字符串取值**的读法纯件：支持的动作、播放状态、位置、音量。
///
/// 设备报的格式参差（缺字段、`NOT_IMPLEMENTED`、大小写不一），每条读法都
/// 落到一个**显式兜底**上，不抛——投屏是遥控一块别人家的屏，读不懂不能把
/// 界面卡住。
library;

import 'cast_session.dart';

/// 读 `GetCurrentTransportActions` 的 `Actions`（CSV）。
///
/// 不认识的词忽略、重复的不重复、缺字段或空串是**空集**——探测不到与设备
/// 自述什么都没有同一口径（哪一项都不显示）。
CastTransportActions parseCastTransportActions(String? actions) {
  if (actions == null) return const CastTransportActions.none();
  final parsed = <CastTransportAction>{};
  for (final raw in actions.split(',')) {
    switch (raw.trim().toLowerCase()) {
      case 'play':
        parsed.add(CastTransportAction.play);
      case 'pause':
        parsed.add(CastTransportAction.pause);
      case 'stop':
        parsed.add(CastTransportAction.stop);
      case 'seek':
        parsed.add(CastTransportAction.seek);
      case 'next':
        parsed.add(CastTransportAction.next);
      case 'previous':
        parsed.add(CastTransportAction.previous);
    }
  }
  return CastTransportActions(parsed);
}

/// 读 `CurrentTransportState`。陌生的取值归 [CastPlaybackState.unknown]：
/// **不猜成停止**——那会让界面在设备还在播时报一个错的态。
CastPlaybackState parseCastPlaybackState(String? state) {
  switch (state?.trim().toUpperCase()) {
    case 'PLAYING':
      return CastPlaybackState.playing;
    case 'PAUSED_PLAYBACK':
    case 'PAUSED_RECORDING':
    case 'PAUSED':
      return CastPlaybackState.paused;
    case 'STOPPED':
      return CastPlaybackState.stopped;
    case 'TRANSITIONING':
      return CastPlaybackState.transitioning;
    case 'NO_MEDIA_PRESENT':
      return CastPlaybackState.noMedia;
    default:
      return CastPlaybackState.unknown;
  }
}

/// 读 `RelTime` / `AbsTime` 这类 `H+:MM:SS[.F+]` 时间串。
///
/// 缺字段、`NOT_IMPLEMENTED`、格式不对、负数一律 [Duration.zero]——位置读不
/// 出时按片头算，是这条路上最不坏的一个谎。
Duration parseCastDuration(String? value) {
  final trimmed = value?.trim() ?? '';
  final parts = trimmed.split(':');
  if (parts.length != 3) return Duration.zero;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  final seconds = double.tryParse(parts[2]);
  if (hours == null || minutes == null || seconds == null) return Duration.zero;
  if (hours < 0 || minutes < 0 || seconds < 0) return Duration.zero;
  final milliseconds = ((hours * 3600 + minutes * 60) * 1000 + seconds * 1000)
      .round();
  return Duration(milliseconds: milliseconds);
}

/// 装配 `Seek` 的 `Target`：`H:MM:SS`（REL_TIME 只到秒）。
String formatCastDuration(Duration position) {
  final milliseconds = position.inMilliseconds < 0
      ? 0
      : position.inMilliseconds;
  final totalSeconds = milliseconds ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return '$hours:${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// 读 `CurrentVolume`（UPnP 是 0–100 的整数）成 0..1。
///
/// 读不出返回 **null**（不假装音量是零——那会在界面上显示一个用户没设过的
/// 值）；超出 0–100 同样按读不出算。
double? parseCastVolume(String? value) {
  final level = int.tryParse(value?.trim() ?? '');
  if (level == null || level < 0 || level > 100) return null;
  return level / 100;
}

/// 装配 `DesiredVolume`：0..1 钳到 0–100 的整数串。
String formatCastVolume(double volume) {
  final clamped = volume.isNaN ? 0.0 : volume.clamp(0.0, 1.0);
  return (clamped * 100).round().toString();
}
