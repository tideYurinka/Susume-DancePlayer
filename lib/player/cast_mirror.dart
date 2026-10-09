/// 投屏遥控镜像口：投屏态内本机的播放 / 暂停 / 跳转**同时**作用于接收端。
///
/// 它是一道**窄缝**：播放内核与 seek 域只认这三个动作，不认识投屏会话、
/// 递出通道与模式值；实现（`cast_run.dart` 的投屏运行域）自己收口失败——
/// **本口不抛**（一次投屏失败不该把本机播放带停）。未接投屏的宿主与测试用
/// [NoCastMirror]（三动作皆空操作）。
library;

/// 投屏遥控镜像口。
abstract interface class CastMirror {
  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);
}

/// 未接投屏的镜像口：三动作都是空操作。
class NoCastMirror implements CastMirror {
  const NoCastMirror();

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}
}
