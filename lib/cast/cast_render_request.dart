/// 投屏渲染请求与**缓存键**（纯件，零 Flutter、零 IO）：投屏渲染要吃的那几样
/// 输入，以及由它们算出的那把缓存键。
///
/// ## 键 = 六个分量（ADR-0005 与规格的口径，分辨率档是 #36 加上的那一维）
///
/// **视频标识 + 渲染勾选档 + 渲染分辨率档 + 影响产物的设置快照 + 投屏倍速档 +
/// 标注内容指纹**。任一分量变一次就换一把键——「改了要重新渲染」因此不是界面
/// 纪律，而是键的结构性后果：旧产物与新键对不上，缓存只会漏，不会命中一份过时
/// 的副本。**分辨率档**同理：保证 1× 实时与降到 720p 渲出来的画面尺寸不同，
/// 两份因此各占一把键（降级与不降级不互相命中）。
///
/// 设置快照按规格叫「**影响画面的设置快照**」；这里把**声音类**那几项
/// （半拍声开关、节拍音量、响度基准、音源）一并收进同一份快照——它们同样
/// 改一次产物就作废一次，键少收一样就会拿「音量改过」的旧音轨去投。画/声
/// 两类的设置同处一型，分量语义仍逐项可辨。
///
/// ## 暂存输入（#47）
///
/// [CastRenderStaging] 也住本件：它是编排层备好边车之后交给命令装配的那份
/// **类型化输入**（哪几样边车、各在 `-i` 里的第几路）。装配层因此不必从勾选档
/// 把「这次装什么」推导第二遍，路径与下标也不会两处各写一遍。
///
/// ## 边界
///
/// 本件是**值对象与算术**：不读盘、不建目录、不构命令。命令装配在
/// `cast_render_plan.dart`，命中/落定在 `cast_render_cache.dart`，编排在
/// `cast_render_orchestrator.dart`。
library;

import 'dart:typed_data';

import '../annotation/framing_selection.dart';
import '../core/local_mirror_fragment.dart';
import 'cast_beat_count.dart';
import 'cast_encoder_realtime.dart';
import 'cast_range_gate.dart' show CastRange;

/// 渲染勾选档：**画面类**（含呈现类）与**声音类**两档。
///
/// 默认全选（面板的初始值）；都不勾 = 直接推原片、零等待。
class CastRenderChoices {
  const CastRenderChoices({required this.picture, required this.sound});

  /// 默认：两档都勾（面板打开时的取值）。
  const CastRenderChoices.all() : picture = true, sound = true;

  /// 都不勾：不渲染，直接推原片。
  const CastRenderChoices.none() : picture = false, sound = false;

  /// 画面类（全局镜像、局部镜像、取景、备注贴纸与呈现类）。
  final bool picture;

  /// 声音类（拍声混进音轨）。
  final bool sound;

  /// 要不要渲染：都不勾 = 不渲染（直接推原片）。
  bool get renders => picture || sound;

  CastRenderChoices copyWith({bool? picture, bool? sound}) => CastRenderChoices(
    picture: picture ?? this.picture,
    sound: sound ?? this.sound,
  );

  /// 档位记号（进缓存键；四种组合互异）。
  String get token => '${picture ? '1' : '0'}${sound ? '1' : '0'}';

  @override
  bool operator ==(Object other) =>
      other is CastRenderChoices &&
      other.picture == picture &&
      other.sound == sound;

  @override
  int get hashCode => Object.hash(picture, sound);

  @override
  String toString() => 'CastRenderChoices(picture: $picture, sound: $sound)';
}

/// 投屏倍速档：投屏只认三档，**一档一份副本**（换倍速 = 让接收端换文件播）。
enum CastSpeedTier {
  half(0.5, '0.5'),
  threeQuarter(0.75, '0.75'),
  full(1, '1');

  const CastSpeedTier(this.rate, this.token);

  /// 这一档的播放倍率（`setpts` / `atempo` 的入参）。
  final double rate;

  /// 档位记号（进缓存键）。
  final String token;
}

/// 这一档这次要不要**重编码视频**。
///
/// 勾了画面类当然要（画面内容要烤进去）；只勾声音类时只有**非 1× 档**要
/// （`-c:v copy` 改不了时长）。它是这一维的**唯一判据**：命令装配
/// （`cast_render_plan.dart`）与范围闸门（`cast_range_gate.dart` 的
/// `castActiveRangeOf`：复制档收不了范围）都读它，谁也不手写第二份；准备面板
/// 那句「这一份降到 720p」也按它决定说不说（视频原样复制的档没有可降的编码，
/// 说了就是假话，`#36`）。
///
/// 它住在这里（请求与勾选档的旁边）而不是命令装配那一侧，是因为它的输入只有
/// [CastRenderChoices] 与 [CastSpeedTier]，而读到它的一方（范围闸门）不该因此
/// 依赖整条命令行的装配件。
bool castRenderReencodesVideo(CastRenderChoices choices, CastSpeedTier tier) =>
    choices.picture || tier != CastSpeedTier.full;

/// **影响渲染产物的设置快照**（规格里的「影响画面的设置快照」，声音类那几项
/// 同样收在这里——见库头）。
///
/// 逐项都是**用户改得动、且改一次产物就得重做**的设置；字段名与取值来源
/// （各设置槽 / 取景会话态 / 节拍呈现开关）由播放页的装配处一一对应。
///
/// 判等与缓存键的记号**同源**：每一格在 [_CastRenderSetting] 的声明表里写一次
/// 它进键的那一段记号，[token] 与 [operator ==] 都由那张表派生——**加一个字段
/// = 枚举加一项 → 穷尽 switch 编译报错**，不存在「加了字段却忘了同步手拼串、
/// 于是缓存失效静默停止工作」这条漏路（`#47`）。
class CastRenderSettings {
  const CastRenderSettings({
    this.globalMirrored = false,
    this.localMirrorEnabled = true,
    this.beatCountVisible = false,
    this.beatAnimationStyle = '',
    this.beatOverlay = '',
    this.stickerOverlay = '',
    this.framing = '',
    this.halfBeatSoundEnabled = false,
    this.metronomeVolumePercent = 50,
    this.songLoudnessBaseline = 1,
    this.metronomeSourceId = 'normal',
  });

  /// 全局镜像（整支视频的镜像开关）。
  final bool globalMirrored;

  /// 局部镜像总开关（关时片段整组不参与）。默认开，与 markers `meta` 段的
  /// 缺键兜底一致。
  final bool localMirrorEnabled;

  /// 数拍 / 节拍动画在屏上是否显示。
  final bool beatCountVisible;

  /// 节拍动画形态的取值名（空 = 该形态未定，按手机默认）。
  final String beatAnimationStyle;

  /// **数拍层的落位记号**（`#30`；空 = 这支舞这次不装数拍层）：数拍那一行在
  /// **画面区域**上的归一化落位（`player/cast_beat_placement.dart` 的
  /// `CastBeatPlacement.token`）。
  ///
  /// 它是**影响产物**的设置：用户把浮层挪一下、转个屏或改一下尺寸系数，都该
  /// 换一把缓存键（否则会命中一份落位不对的旧副本）。故它进设置快照的记号。
  final String beatOverlay;

  /// **备注贴纸的尺寸记号**（`#21` 整改；空 = 这次不装贴纸）：逐条贴纸的
  /// **归一化尺寸分数**（`CastSticker.sizeToken`，次序即请求里的贴纸次序）。
  ///
  /// 贴纸的**内容**（文本、几何、时间窗、名册取色）已在
  /// [CastRenderRequest.annotationFingerprint] 里；**尺寸**不是——两个分数是
  /// 装配期从「上屏量测到的墨迹逻辑尺寸 ÷ 上屏画面矩形」现算的
  /// （`player/cast_render_wiring.dart`），于是系统字号缩放与画面矩形（转屏）
  /// 都会改产物却没有痕迹。按 [beatOverlay] 的既有先例，把它们收进设置快照
  /// 的记号：改系统字号或换画面矩形即换键（否则会命中一份大小不对的旧副本）。
  final String stickerOverlay;

  /// 取景选区的规范串（空 = 未取景 = 整帧）。
  final String framing;

  /// 半拍声开关（有半拍线时决定半拍声进不进音轨）。
  final bool halfBeatSoundEnabled;

  /// 节拍音量（0–100）。
  final int metronomeVolumePercent;

  /// 这支舞的响度基准（节拍声响度的另一半）。
  final double songLoudnessBaseline;

  /// 音源取值（`normal` / `vocal` / `geigi`）。
  final String metronomeSourceId;

  /// 进缓存键的记号：逐格声明的记号按声明次序拼起来（**不手写这一串**）。
  String get token => [
    for (final id in _CastRenderSetting.values) _tokenOfSetting(this, id),
  ].join('|');

  /// 相等 = 每一格的**进键记号**都相同——与 [token] 读同一张声明表，判等与
  /// 键摘要因此不可能一边变一边不变。
  @override
  bool operator ==(Object other) {
    if (other is! CastRenderSettings) return false;
    if (identical(this, other)) return true;
    for (final id in _CastRenderSetting.values) {
      if (_tokenOfSetting(this, id) != _tokenOfSetting(other, id)) return false;
    }
    return true;
  }

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'CastRenderSettings($token)';
}

/// 设置快照的一格（`#47`）：**加一个字段 = 这里加一项**，[token] 与判等自动
/// 跟随（穷尽 switch 让漏掉的那一格编译报错）。
enum _CastRenderSetting {
  globalMirrored,
  localMirrorEnabled,
  beatCountVisible,
  beatAnimationStyle,
  beatOverlay,
  stickerOverlay,
  framing,
  halfBeatSoundEnabled,
  metronomeVolumePercent,
  songLoudnessBaseline,
  metronomeSourceId,
}

/// 一格的进键记号（该字段在缓存键里的那一段）。**这是每一格唯一的声明处**：
/// 键的拼接、判等、哈希都读它。
String _tokenOfSetting(CastRenderSettings settings, _CastRenderSetting id) =>
    switch (id) {
      _CastRenderSetting.globalMirrored =>
        settings.globalMirrored ? 'gm1' : 'gm0',
      _CastRenderSetting.localMirrorEnabled =>
        settings.localMirrorEnabled ? 'lm1' : 'lm0',
      _CastRenderSetting.beatCountVisible =>
        settings.beatCountVisible ? 'bc1' : 'bc0',
      _CastRenderSetting.beatAnimationStyle =>
        'ba:${settings.beatAnimationStyle}',
      _CastRenderSetting.beatOverlay => 'bov:${settings.beatOverlay}',
      _CastRenderSetting.stickerOverlay => 'sto:${settings.stickerOverlay}',
      _CastRenderSetting.framing => 'fr:${settings.framing}',
      _CastRenderSetting.halfBeatSoundEnabled =>
        settings.halfBeatSoundEnabled ? 'hb1' : 'hb0',
      _CastRenderSetting.metronomeVolumePercent =>
        'vol:${settings.metronomeVolumePercent}',
      _CastRenderSetting.songLoudnessBaseline =>
        'loud:${settings.songLoudnessBaseline.toStringAsFixed(4)}',
      _CastRenderSetting.metronomeSourceId =>
        'src:${settings.metronomeSourceId}',
    };

/// 一条拍声：这一拍在**源视频时间轴**的哪个时刻、放哪一段资产、多大音量。
///
/// 排程由播放页侧派生（读节拍网格、音源段表、半拍线与音量设置）——投屏域
/// 不 import 播放页，派生结果作为数据传进来。拍声轨（`cast_beat_track.dart`）
/// 把它合成为一条 WAV，混进副本音轨。
class CastBeatClick {
  const CastBeatClick({
    required this.time,
    required this.asset,
    required this.volume,
  });

  /// 拍点在源视频时间轴上的时刻。
  final Duration time;

  /// 段资产路径（随包内置的 WAV）。
  final String asset;

  /// 这一拍的样本级响度（0–1），与手机本地播放同一口径。
  final double volume;

  @override
  bool operator ==(Object other) =>
      other is CastBeatClick &&
      other.time == time &&
      other.asset == asset &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(time, asset, volume);

  @override
  String toString() => 'CastBeatClick($time, $asset, $volume)';
}

/// **一条备注贴纸的第二路输入**：一张带 alpha 的**单帧 PNG** + 它的时间窗与
/// 落位（`#29`）。
///
/// ## 与上屏同源的两样东西
///
/// - [centerX] / [centerY] 是贴纸几何在**源画面矩形**上的归一化中心——文档里
///   那一份 `NoteGeometry` 的中心，与上屏求值读同一个值；取景窗口换算、随面
///   翻转与钳制由 `cast_sticker_gate.dart` 按上屏同一套口径算（不在这里预烘）。
/// - [widthFraction] / [heightFraction] 是贴纸**可见墨迹**尺寸占**上屏画面
///   矩形**（取景后那一块，也就是投屏副本的帧）的比例——上屏量测到的贴纸尺寸
///   除以画面矩形即这两个分数，故电视上的贴纸与手机上的贴纸占同一块画面的
///   同一个比例；倍速档、源分辨率都不进这两个数。
///
/// [imageBytesOf] 是**播放页侧**按上屏同一份 span 与样式光栅化的那一步
/// （`player/cast_sticker_sheet.dart`）：一个**惰性**的取字节口。装配处（它是
/// 同步的）只在这里给出「渲染那一刻去画」这件事，真正画字的时刻是渲染编排写
/// 文件的时候——投屏域因此不 import 播放页、也不自己画字，图的字节由播放页
/// 那一侧产出。
class CastSticker {
  const CastSticker({
    required this.imageBytesOf,
    required this.startMs,
    required this.endMs,
    required this.centerX,
    required this.centerY,
    required this.widthFraction,
    required this.heightFraction,
  });

  /// 带 alpha 的单帧 PNG 字节（惰性：渲染编排落盘时现取）。
  final Future<Uint8List> Function() imageBytesOf;

  /// 时间窗起点（毫秒，含）。
  final int startMs;

  /// 时间窗终点（毫秒，不含——半开区间）。
  final int endMs;

  /// 源画面矩形归一化中心横坐标（与文档 `NoteGeometry.centerX` 同一个值）。
  final double centerX;

  /// 源画面矩形归一化中心纵坐标。
  final double centerY;

  /// 宽度占上屏画面矩形的比例（含描边墨迹的余量）。
  final double widthFraction;

  /// 高度占上屏画面矩形的比例。
  final double heightFraction;

  /// 时间窗（半开）是否为空：空窗不装任何节点。
  bool get visible => endMs > startMs;

  /// 进缓存键的**尺寸分量**记号：两个归一化分数由「上屏量测的墨迹逻辑尺寸 ÷
  /// 上屏画面矩形」派生（装配处 `player/cast_render_wiring.dart`），系统字号
  /// 缩放与画面矩形（转屏）都会改它们——键少收这一样就会命中一份大小不对的
  /// 旧副本。与 `CastBeatPlacement.token` 同款先例（那边记的是落位）。
  String get sizeToken =>
      'st:${widthFraction.toStringAsFixed(6)}x'
      '${heightFraction.toStringAsFixed(6)}';

  @override
  bool operator ==(Object other) =>
      other is CastSticker &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.centerX == centerX &&
      other.centerY == centerY &&
      other.widthFraction == widthFraction &&
      other.heightFraction == heightFraction;
  // 注意：字节不进相等判等（它由文本、几何、时间窗与名册唯一决定，那几样都在
  // 标注指纹里；两个请求的贴纸几何相同就是同一次输入）。

  @override
  int get hashCode => Object.hash(
    startMs,
    endMs,
    centerX,
    centerY,
    widthFraction,
    heightFraction,
  );

  @override
  String toString() =>
      'CastSticker($startMs–$endMs, $centerX/$centerY, '
      '$widthFraction×$heightFraction)';
}

/// **一路边车输入**（源片之外的 `-i`）：它的路径 + 它在命令行里的下标。
///
/// 路径与下标**成对给全**：`-i` 追加的是哪个文件、滤镜图引用的是哪一号输入，
/// 两处读的是同一个数（`#47`）——「第几路」不再由装配层另算一遍。
class CastRenderSidecar {
  const CastRenderSidecar({required this.path, required this.index});

  /// 这一路输入的文件路径。
  final String path;

  /// 它在 `-i` 里的下标（源片恒是 0 号）。
  final int index;

  @override
  bool operator ==(Object other) =>
      other is CastRenderSidecar && other.path == path && other.index == index;

  @override
  int get hashCode => Object.hash(path, index);

  @override
  String toString() => 'CastRenderSidecar($index: $path)';
}

/// **一条贴纸图输入**：贴纸与它的图**成对**——不是两张可能对不上的平行表。
class CastStickerInput {
  const CastStickerInput({required this.sticker, required this.sidecar});

  final CastSticker sticker;

  final CastRenderSidecar sidecar;

  @override
  String toString() => 'CastStickerInput(${sidecar.index}: $sticker)';
}

/// **数拍序列清单输入**：清单与它要装的**数拍层**成对（装了数拍层才有这一路）。
class CastBeatSlidesInput {
  const CastBeatSlidesInput({required this.overlay, required this.sidecar});

  /// 要装的数拍层（逐拍行与落位）。
  final CastBeatCountOverlay overlay;

  final CastRenderSidecar sidecar;

  @override
  String toString() =>
      'CastBeatSlidesInput(${sidecar.index}: ${sidecar.path})';
}

/// **一次渲染的暂存输入**（`#47`）：编排层按请求刚备好的那几样边车文件与它们
/// 在 `-i` 里的下标。命令装配读它落命令，**不再从勾选档把「这次装什么」推导
/// 第二遍**。
///
/// - [beatTrack] 空 = 这次不混拍声（勾了声音类时编排层已备好那条轨）；
/// - [beatSlides] 空 = 这次不装数拍层；
/// - [stickers] 空表 = 这次没有贴纸图。
///
/// 「勾了声音类却没有拍声轨」「贴纸图与贴纸对不上」「要装数拍层却没有清单」这
/// 三种组合因此没有位置——它们都是同一件事写成两处、两处对不齐的产物，而这里
/// 只有一处。
class CastRenderStaging {
  const CastRenderStaging({
    this.beatTrack,
    this.beatSlides,
    this.stickers = const [],
  });

  /// 拍声轨（勾了声音类才有）。
  final CastRenderSidecar? beatTrack;

  /// 数拍序列清单（装了数拍层才有）。
  final CastBeatSlidesInput? beatSlides;

  /// 贴纸图（与请求里的贴纸一一成对）。
  final List<CastStickerInput> stickers;

  @override
  String toString() =>
      'CastRenderStaging(beatTrack: $beatTrack, beatSlides: $beatSlides, '
      'stickers: ${stickers.length})';
}

/// 一次投屏渲染的全部输入。
class CastRenderRequest {
  const CastRenderRequest({
    required this.videoPath,
    required this.videoId,
    required this.duration,
    required this.choices,
    required this.speedTier,
    this.resolution = CastRenderResolution.source,
    required this.settings,
    required this.annotationFingerprint,
    this.mirrorFragments = const [],
    this.framingSelection,
    this.stickers = const [],
    this.beatOverlay,
    this.beatClicks = const [],
    this.range,
  });

  /// 源**视频副本**路径（渲染的输入；副本丢失时根本没有这一票）。
  final String videoPath;

  /// 这支舞的**视频标识**（缓存键的第一分量）。
  final String videoId;

  /// 素材**整片**时长（拍声轨按它合成，范围与进度分母都以它为基准——进度的
  /// 分母是**副本**的期望时长，见 `cast_range_gate.dart` 的
  /// `castCopyDurationOf`）。
  final Duration duration;

  final CastRenderChoices choices;

  final CastSpeedTier speedTier;

  /// **渲染分辨率档**（缓存键的一维，也是画面链尾那个缩放节点与码率的来源）。
  ///
  /// 由**准备面板**按编码器能力三态定：保证 1× 实时 = 源档（按源分辨率），
  /// 不保证与**问不到** = 720p（见 `cast_encoder_realtime.dart`）。默认源档，
  /// 于是既有构造点不必改。
  final CastRenderResolution resolution;

  final CastRenderSettings settings;

  /// 这支舞**标注内容**的指纹（`cast_annotation_fingerprint.dart`）。
  final String annotationFingerprint;

  /// **局部镜像片段表**（源时间轴、升序、两两不重叠、半开区间）。
  ///
  /// 与上屏求值读**同一份**取值：装配处（`player/cast_render_wiring.dart`）读一次
  /// 片段 provider，一路进指纹、一路进这里，画面滤镜链的局部镜像闸门按它成窗
  /// （见 `cast_mirror_gate.dart`）。空表 = 没有局部镜像片段。
  ///
  /// 它**不是缓存键的独立分量**：片段内容是标注内容的一部分，已在
  /// [annotationFingerprint] 里；改片段即换指纹、即换键。
  final List<LocalMirrorFragment> mirrorFragments;

  /// **取景选区**（四边按源画面矩形归一化；`null` = 未调过 = 整帧）。
  ///
  /// 与上屏、与缓存键读**同一份**取值：装配处（`player/cast_render_wiring.dart`）
  /// 读一次 `framingStateProvider.source`，一路写进 [CastRenderSettings.framing]
  /// （规范串，进缓存键），一路写进这里（画面链的裁切窗口按它成窗，见
  /// `cast_framing_gate.dart`）。两处因此不是各自读一遍、各自对齐的口径。
  ///
  /// 它**不是缓存键的独立分量**：取景取值的规范串已在 [settings] 的记号里
  /// （`fr:…`），改选区即换键。
  final FramingSelection? framingSelection;

  /// **备注贴纸的第二路输入**（`#29`；空表 = 这支舞没有备注）。
  ///
  /// 与上屏求值读**同一份**取值：装配处（`player/cast_render_wiring.dart`）
  /// 读一次 `noteStickersProvider`，一路进标注指纹、一路在这里成图与落位。
  /// 它**不是缓存键的独立分量**：贴纸内容（文本、几何、时间窗）已在
  /// [annotationFingerprint] 里（只有名册取色影响这张图，名册同样在指纹里）；
  /// **尺寸**（由系统字号与上屏画面矩形现算的两个分数）在
  /// [CastRenderSettings.stickerOverlay] 记号里——两处合起来，贴纸的任一样
  /// 变了都换键。
  final List<CastSticker> stickers;

  /// **数拍层**（`#30`；null = 不装这一层：没勾画面类、数拍显示关着、
  /// 网格异常，或落位量不出来）。
  ///
  /// 与上屏求值读**同一份**取值：装配处（`player/cast_render_wiring.dart`）
  /// 逐拍走节拍呈现的同一条 `evaluatePresentationValue` 派生文字，落位走
  /// `player/cast_beat_placement.dart` 的视口 → 画面区域换算。它**不是缓存键的
  /// 独立分量**：数拍显示开关与节拍动画形态在 [settings] 里，落位在
  /// [CastRenderSettings.beatOverlay] 记号里，拍点与锚点在
  /// [annotationFingerprint] 里；任一样变了都换键。
  final CastBeatCountOverlay? beatOverlay;

  /// 拍声排程（声音类用；画面类不看它）。
  final List<CastBeatClick> beatClicks;

  /// **投屏副本的范围**（`#37`；源时间轴上的半开区间）：这支舞的
  /// **首线 → 尾线**，`null` = 整片。
  ///
  /// 与上屏、与缓存键读**同一份**取值：装配处（`player/cast_render_wiring.dart`）
  /// 读一次 `annotationTimelineProvider` 的 `rangeStart` / `rangeEnd`，写进这里；
  /// 画面链的 `trim` 与音轨链的 `atrim` 按它成窗（见 `cast_range_gate.dart`）。
  ///
  /// 它**不是缓存键的独立分量**：首尾区间已在 [annotationFingerprint] 里
  /// （`cast_annotation_fingerprint.dart` 的 `'range'` 那一项），改首尾线即换
  /// 指纹、即换键——重复收一次只会让键更长。
  final CastRange? range;

  /// 这份请求对应的缓存键。
  CastRenderKey get cacheKey => CastRenderKey(
    videoId: videoId,
    choices: choices,
    resolution: resolution,
    settings: settings,
    speedTier: speedTier,
    annotationFingerprint: annotationFingerprint,
  );
}

/// 投屏缓存键：各分量各自的记号按固定次序拼成一条可读串（**视频标识 +
/// 渲染勾选档 + 渲染分辨率档 + 影响产物的设置快照 + 投屏倍速档 + 标注内容
/// 指纹**）。
///
/// 「分辨率档」是 #36 加上的那一维：同一支舞、同一勾选、同一倍速档，在降级
/// 与不降级下是**两份不同的缓存条目**，不得互相命中。
///
/// 可读串进缓存文件名前会经一次摘要（`cast_render_cache.dart`），因此这里
/// 不含路径分隔符与非法字符的裁剪规则。
class CastRenderKey {
  const CastRenderKey({
    required this.videoId,
    required this.choices,
    this.resolution = CastRenderResolution.source,
    required this.settings,
    required this.speedTier,
    required this.annotationFingerprint,
  });

  final String videoId;
  final CastRenderChoices choices;
  final CastRenderResolution resolution;
  final CastRenderSettings settings;
  final CastSpeedTier speedTier;
  final String annotationFingerprint;

  /// 键的可读记号（分量次序即上面的字段次序，用 `#` 分隔）。
  String get token => [
    videoId,
    choices.token,
    resolution.token,
    settings.token,
    speedTier.token,
    annotationFingerprint,
  ].join('#');

  @override
  bool operator ==(Object other) =>
      other is CastRenderKey && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'CastRenderKey($token)';
}
