import '../persistence/song_signature.dart';

/// 命名场景：导入命名（三字段空）/ 改名（保留现值）。
enum SongNamingScene { import, rename }

/// 命名/改名对话框的各字段初值。
class SongNamingInitial {
  const SongNamingInitial({
    required this.song,
    required this.dancer,
    required this.remark,
  });

  /// 歌曲名初值：导入 = 空；改名 = 现歌名（无现值回退该回退名——「文件名
  /// 回落名」，已去扩展名）。
  final String song;

  /// 舞者名初值：导入为空；改名保留原值。
  final String dancer;

  /// 注记初值：导入为空；改名保留原值。
  final String remark;
}

/// 初值规则：给定场景、现值与回退名（[fallbackName] = 「文件名回落名」，即
/// 去扩展名的文件名，由调用侧的读面经 `songFallbackName` 取好），输出各字段
/// 初值。导入三字段恒为空；改名保留现值（无现值歌曲名回退该回退名——把文件名
/// 改成歌名的入口语义）。
SongNamingInitial resolveSongNamingInitial({
  required SongNamingScene scene,
  required SongSignature? current,
  required String fallbackName,
}) {
  if (scene == SongNamingScene.import) {
    return const SongNamingInitial(song: '', dancer: '', remark: '');
  }
  final value = current ?? SongSignature(song: fallbackName);
  return SongNamingInitial(
    song: value.song,
    dancer: value.dancer,
    remark: value.remark,
  );
}

/// 命名对话框的一次结论。
class SongNamingResult {
  const SongNamingResult({required this.confirmed, required this.signature});

  /// true = 用户点了「保存」；false = 按了退路钮（导入 = 「跳过（按文件名
  /// 命名）」、改名 = 「取消」）——语义由域按场景收口。
  final bool confirmed;

  /// 输入框现值（未净化；净化与回退由宿主经控制器统一处理）。
  final SongSignature signature;
}
