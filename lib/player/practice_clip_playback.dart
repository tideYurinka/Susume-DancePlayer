import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/compare_materials.dart';
import '../core/playback/media_kit_playback_engine.dart';
import '../core/playback/playback_engine.dart';

/// 练习片段回放的第二个播放源注入点：练习侧
/// 回看画面专用引擎——与会话主引擎（源侧）分立，互不干扰各自的播放位
/// 置与循环作用域。生产默认 media_kit 适配器（与主引擎同款）；测试用
/// FakePlaybackEngine 覆盖（`overrideWithValue`）。懒建：只在片段激活
/// 接线首次读取时构造，普通播放会话零开销。
///
/// ProviderScope 销毁时释放内核资源（[PlaybackEngine.dispose]）。
final practiceClipEngineProvider = Provider<PlaybackEngine>((ref) {
  final engine = MediaKitPlaybackEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// 练习片段回放控制器：把激活片段的素材文件
/// 按**截取范围**送到练习侧第二播放源——打开素材、定位截取起点、随播
/// 放位置在截取终点回卷截取起点（区间内直循环，无循环前导）。纯薄层，
/// 不把播放逻辑带进 UI。
///
/// 素材内偏移即引擎位置（第二引擎打开的源 = 素材文件本身），换算只在
/// [PracticeClip] 的 in/out 偏移与 [Duration] 之间发生，一处收口。
class PracticeClipPlaybackController {
  PracticeClipPlaybackController({
    required this.engine,
    required this.resolveSource,
  });

  final PlaybackEngine engine;

  /// 素材文件解析缝：按片段找回素材文件 URI（清单 + 私有素材目录）；
  /// 返回 null = 解析失败（静默不回放）。
  final Future<Uri?> Function(PracticeClip clip) resolveSource;

  PracticeClip? _current;

  StreamSubscription<Duration>? _positionSubscription;

  /// 当前回放的片段；null = 未在回放（未激活）。
  PracticeClip? get current => _current;

  /// 就位片段回放：打开素材文件、seek 截取起点，[autoplay] 时开始播
  /// （用户点选激活 = 跟随源侧当前播放态；恢复就位 = false，不自动播）。
  /// 返回回放是否就位：解析失败（素材缺失/清单不可读，= 播放源无效）
  /// 或已被更新的激活取代返回 false，调用方据此停播退出回看。
  Future<bool> show(PracticeClip clip, {required bool autoplay}) async {
    _current = clip;
    final source = await resolveSource(clip);
    if (source == null || _current != clip) return false;
    await engine.open(source);
    await engine.seek(Duration(milliseconds: clip.inMs));
    if (autoplay) await engine.play();
    // 截取范围内直循环（无循环前导——到 out 直接回 in）。
    final inPoint = Duration(milliseconds: clip.inMs);
    final outPoint = Duration(milliseconds: clip.outMs);
    _positionSubscription?.cancel();
    _positionSubscription = engine.positionStream.listen((position) {
      if (position >= outPoint) {
        unawaited(engine.seek(inPoint));
      }
    });
    return true;
  }

  /// 退出回放：停循环看护与播放（画面随激活面退场）。
  void hide() {
    _current = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    engine.pause();
  }

  /// 跟随源侧播放态（练习侧回放与源侧同起同停；未在回放时零行为）。
  Future<void> syncPlaying(bool playing) async {
    if (_current == null) return;
    if (playing) {
      await engine.play();
    } else {
      await engine.pause();
    }
  }

  void dispose() {
    _current = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }
}
