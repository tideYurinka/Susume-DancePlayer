/// 投屏渲染请求与**缓存键**（纯件，零 Flutter、零 IO）：投屏渲染要吃的那几样
/// 输入，以及由它们算出的那把缓存键。
///
/// ## 键 = 五个分量（ADR-0005 与规格的口径）
///
/// **视频标识 + 渲染勾选档 + 影响产物的设置快照 + 投屏倍速档 + 标注内容指纹**。
/// 任一分量变一次就换一把键——「改了要重新渲染」因此不是界面纪律，而是键的
/// 结构性后果：旧产物与新键对不上，缓存只会漏，不会命中一份过时的副本。
///
/// 设置快照按规格叫「**影响画面的设置快照**」；这里把**声音类**那几项
/// （半拍声开关、节拍音量、响度基准、音源）一并收进同一份快照——它们同样
/// 改一次产物就作废一次，键少收一样就会拿「音量改过」的旧音轨去投。画/声
/// 两类的设置同处一型，分量语义仍逐项可辨。
///
/// ## 边界
///
/// 本件是**值对象与算术**：不读盘、不建目录、不构命令。命令装配在
/// `cast_render_plan.dart`，命中/落定在 `cast_render_cache.dart`，编排在
/// `cast_render_orchestrator.dart`。
library;

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

/// **影响渲染产物的设置快照**（规格里的「影响画面的设置快照」，声音类那几项
/// 同样收在这里——见库头）。
///
/// 逐项都是**用户改得动、且改一次产物就得重做**的设置；字段名与取值来源
/// （各设置槽 / 取景会话态 / 节拍呈现开关）由播放页的装配处一一对应。
/// [token] 是它在缓存键里的记号。
class CastRenderSettings {
  const CastRenderSettings({
    this.globalMirrored = false,
    this.localMirrorEnabled = true,
    this.beatCountVisible = false,
    this.beatAnimationStyle = '',
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

  /// 进缓存键的记号。
  String get token => [
    globalMirrored ? 'gm1' : 'gm0',
    localMirrorEnabled ? 'lm1' : 'lm0',
    beatCountVisible ? 'bc1' : 'bc0',
    'ba:$beatAnimationStyle',
    'fr:$framing',
    halfBeatSoundEnabled ? 'hb1' : 'hb0',
    'vol:$metronomeVolumePercent',
    'loud:${songLoudnessBaseline.toStringAsFixed(4)}',
    'src:$metronomeSourceId',
  ].join('|');

  @override
  bool operator ==(Object other) =>
      other is CastRenderSettings && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'CastRenderSettings($token)';
}

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

/// 一次投屏渲染的全部输入。
class CastRenderRequest {
  const CastRenderRequest({
    required this.videoPath,
    required this.videoId,
    required this.duration,
    required this.choices,
    required this.speedTier,
    required this.settings,
    required this.annotationFingerprint,
    this.beatClicks = const [],
  });

  /// 源**视频副本**路径（渲染的输入；副本丢失时根本没有这一票）。
  final String videoPath;

  /// 这支舞的**视频标识**（缓存键的第一分量）。
  final String videoId;

  /// 素材时长（进度的分母；也是拍声轨的长度）。
  final Duration duration;

  final CastRenderChoices choices;

  final CastSpeedTier speedTier;

  final CastRenderSettings settings;

  /// 这支舞**标注内容**的指纹（`cast_annotation_fingerprint.dart`）。
  final String annotationFingerprint;

  /// 拍声排程（声音类用；画面类不看它）。
  final List<CastBeatClick> beatClicks;

  /// 这份请求对应的缓存键。
  CastRenderKey get cacheKey => CastRenderKey(
    videoId: videoId,
    choices: choices,
    settings: settings,
    speedTier: speedTier,
    annotationFingerprint: annotationFingerprint,
  );
}

/// 投屏缓存键：五个分量各自的记号按固定次序拼成一条可读串。
///
/// 可读串进缓存文件名前会经一次摘要（`cast_render_cache.dart`），因此这里
/// 不含路径分隔符与非法字符的裁剪规则。
class CastRenderKey {
  const CastRenderKey({
    required this.videoId,
    required this.choices,
    required this.settings,
    required this.speedTier,
    required this.annotationFingerprint,
  });

  final String videoId;
  final CastRenderChoices choices;
  final CastRenderSettings settings;
  final CastSpeedTier speedTier;
  final String annotationFingerprint;

  /// 键的可读记号（分量次序即上面的字段次序，用 `#` 分隔）。
  String get token => [
    videoId,
    choices.token,
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
