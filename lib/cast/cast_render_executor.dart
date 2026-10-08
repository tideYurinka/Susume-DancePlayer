/// **渲染执行器**接缝：跑**一条** ffmpeg 命令、回报进度、可取消。
///
/// ## 为什么是投屏域自带的兄弟接缝
///
/// 仓内封面取帧已有同形状的一条（`lib/core/cover_frame.dart` + 真实实现 +
/// Provider + 测试替身），但它的契约是「取一帧」——不含进度与取消，且它属于
/// 封面域。把它泛化会改动既有域，所以投屏域自带一条：接口 + 真实实现
/// （`cast_render_executor_ffmpeg.dart`，走已链接的 ffmpeg 包）+
/// [castRenderExecutorProvider] 注入 + 脚本化替身
/// （`test/helpers/fake_cast_render_executor.dart`）。两者日后若收敛，那是一次
/// 独立重构（规格已定）。
///
/// ## 契约
///
/// - 只跑命令、只报结局：**不碰缓存、不决定产物落位**（那些归编排器）。命令
///   里写哪个输出路径，产物就落在哪。
/// - [run] 成功返回前，命令已经结束；[cancel] 是**另一条**入口（界面上的
///   取消按钮），可以在 [run] 在飞时调用。取消后 [run] 返回
///   [CastRenderVerdict.cancelled]，**不抛**。
/// - 一次只跑一条：同一实例上并发 [run] 是编程错误（本域一次投屏只渲一份）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cast_render_executor_ffmpeg.dart';

/// 一次渲染的结局（三类明确结局，与取消/失败面一一对应）。
enum CastRenderVerdict {
  /// 命令返回码为成功。
  succeeded,

  /// 被 [CastRenderExecutor.cancel] 取消。
  cancelled,

  /// 返回码非成功、或执行器本身报错。
  failed,
}

/// 渲染进度：已渲染到的时长与产物总时长。
class CastRenderProgress {
  const CastRenderProgress({required this.rendered, required this.total});

  /// 已渲染到的位置（ffmpeg 报的 `time`）。
  final Duration rendered;

  /// 产物总时长（进度的分母）：副本覆盖的源跨度（范围生效时是首线→尾线那一段）
  /// 按**投屏倍速档**换算过来的产物期望时长（0.5× 档是它的两倍）——不是源时长
  /// 本身、也不是整片时长。
  final Duration total;

  /// 0..1 的完成比例（总时长未知时恒 0，界面按不定态画）。
  double get fraction {
    if (total <= Duration.zero) return 0;
    final value = rendered.inMicroseconds / total.inMicroseconds;
    if (value.isNaN || value < 0) return 0;
    return value > 1 ? 1 : value;
  }

  @override
  bool operator ==(Object other) =>
      other is CastRenderProgress &&
      other.rendered == rendered &&
      other.total == total;

  @override
  int get hashCode => Object.hash(rendered, total);

  @override
  String toString() => 'CastRenderProgress($rendered / $total)';
}

/// 一条渲染命令（参数表 + 进度分母）。
class CastRenderJob {
  const CastRenderJob({required this.arguments, required this.total});

  /// 交给 ffmpeg 的参数表（`cast_render_plan.dart` 装配）。
  final List<String> arguments;

  /// 产物总时长（进度分母）：副本覆盖的源跨度（范围生效时是首线→尾线那一段）
  /// **按投屏倍速档换算过的**产物期望时长（0.5× 档是两倍；`setpts=PTS/rate` 的
  /// 直接后果，装配见 `cast_render_orchestrator.dart` 与 `cast_range_gate.dart`）。
  final Duration total;
}

/// 渲染执行器接缝。
abstract interface class CastRenderExecutor {
  /// 跑一条命令；[onProgress] 可以调多次（实现按 ffmpeg 的统计回调转发）。
  Future<CastRenderVerdict> run(
    CastRenderJob job, {
    void Function(CastRenderProgress progress)? onProgress,
  });

  /// 取消正在跑的那条命令；未在跑时是空操作，重复调用也是空操作。
  Future<void> cancel();
}

/// 渲染执行器的注入点：真实实现走已链接的 ffmpeg 包；测试 override 注入
/// 脚本化替身，不跑进程。
final castRenderExecutorProvider = Provider<CastRenderExecutor>(
  (ref) => FfmpegCastRenderExecutor(),
);
