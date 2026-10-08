/// **编码器 1× 实时能力**与**渲染分辨率档**（纯件，零 Flutter、零 IO）。
///
/// ## 三态，不是 bool
///
/// 投屏渲染前要问系统一件事：这台机器的编码器**保证** 1× 实时吗？答案有三种，
/// 而**第三态正是兜底决策的落点**——别把它压成 false：
///
/// - [CastEncoderRealtime.guaranteed]：系统给出的编码器性能点覆盖得了这一档
///   （1080p / 30fps），按**源分辨率**渲；
/// - [CastEncoderRealtime.notGuaranteed]：性能点答得出来、但覆盖不了，**降到
///   720p**；
/// - [CastEncoderRealtime.unknown]：问不到——系统这门 API 不在（性能点是
///   **API 29+**，而本仓 `minSdk` 是 24）、设备不报、通道不在、查询报错。
///
/// **兜底取「按不可保证处理」**（[castRenderResolutionFor]）：问不到就等于不
/// 保证，一律降级。理由是它与上位理由同向——宁可降分辨率，也不给用户一个
/// **未知时长的进度条**（ADR-0004 的回填）。
///
/// ## 分辨率档是渲染参数与缓存键的一维
///
/// 同一支舞、同一勾选、同一倍速档，在降级与不降级下是**两份不同的缓存条目**
/// （[CastRenderResolution.token] 进 `CastRenderKey`），不得互相命中。
///
/// 档带两样渲染参数：[CastRenderResolution.scaleNode] 是画面链尾那个缩放节点
/// （源档为 null = 一个节点都不加，链路与今天逐字一致）、
/// [CastRenderResolution.bitrate] 是编码码率。720p 档的缩放**只钉高 720 行、
/// 宽度按源画面比例现算**（`-2` 顺带保证偶数）——它**不拉伸**画面：取景裁出来
/// 的那块窗口不是 16:9 时，硬铺 1280×720 会把人的动作压扁。缩放之后再钉一次
/// `setsar=1`：`scale` 在尺寸变了之后会自己改 SAR 去保 DAR（实测 1080×1920 →
/// 406×720 会写成 `405:406`），方像素得我们钉（与取景闸门那条同款）。
library;

/// 「这台机器的编码器能不能保证 1× 实时」的三态答案（接缝的返回值）。
enum CastEncoderRealtime {
  /// 系统给的性能点覆盖得了这一档：按源分辨率渲。
  guaranteed,

  /// 性能点答得出来、但覆盖不了这一档：降到 720p。
  notGuaranteed,

  /// 问不到（API < 29 / 设备不报 / 通道不在 / 查询失败）：按不可保证处理。
  unknown,
}

/// 源档的编码码率（不降级时的显式码率）。
const String kCastRenderSourceBitrate = '8M';

/// 720p 档的编码码率（像素少了一多半，码率跟着降）。
const String kCastRenderP720Bitrate = '4M';

/// **渲染分辨率档**：投屏渲染输出画面的一维（也是缓存键的一维）。
enum CastRenderResolution {
  /// 源分辨率：不加任何缩放节点（未取景时输出即源尺寸，取景时输出即裁切尺寸）。
  source(token: 'src', bitrate: kCastRenderSourceBitrate, scaleNode: null),

  /// 720p：钉高 720 行、宽度按源画面比例，方像素。
  p720(
    token: '720p',
    bitrate: kCastRenderP720Bitrate,
    scaleNode: 'scale=-2:720,setsar=1',
  );

  const CastRenderResolution({
    required this.token,
    required this.bitrate,
    required this.scaleNode,
  });

  /// 档位记号（进缓存键；两档互异）。
  final String token;

  /// 这一档的显式编码码率（`-b:v`）。
  final String bitrate;

  /// 画面链尾要装的缩放节点；源档为 null（**一个节点都不加**）。
  final String? scaleNode;
}

/// 能力三态 → 这次用哪一档渲染（**纯件**，也是兜底决策的唯一出处）。
///
/// 只有 [CastEncoderRealtime.guaranteed] 不降级；[CastEncoderRealtime.unknown]
/// 与 [CastEncoderRealtime.notGuaranteed] 同路——见库头。
CastRenderResolution castRenderResolutionFor(CastEncoderRealtime capability) {
  return switch (capability) {
    CastEncoderRealtime.guaranteed => CastRenderResolution.source,
    CastEncoderRealtime.notGuaranteed => CastRenderResolution.p720,
    CastEncoderRealtime.unknown => CastRenderResolution.p720,
  };
}
