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

  /// 歌曲名初值：导入 = 空；改名 = 现歌名（无现值回退文件名）。
  final String song;

  /// 舞者名初值：导入为空；改名保留原值。
  final String dancer;

  /// 注记初值：导入为空；改名保留原值。
  final String remark;
}

/// 初值规则：给定场景、现值
/// 与回退文件名，输出各字段初值。导入三字段恒为空；改名保留现值（无现值
/// 歌曲名回退文件名——把文件名改成歌名的入口语义）。
SongNamingInitial resolveSongNamingInitial({
  required SongNamingScene scene,
  required SongSignature? current,
  required String fallbackFileName,
}) {
  if (scene == SongNamingScene.import) {
    return const SongNamingInitial(song: '', dancer: '', remark: '');
  }
  final value = current ?? SongSignature(song: fallbackFileName);
  return SongNamingInitial(
    song: value.song,
    dancer: value.dancer,
    remark: value.remark,
  );
}

/// 命名对话框的一次结论。
class SongNamingResult {
  const SongNamingResult({required this.confirmed, required this.signature});

  /// true = 用户点了「保存」；false = 点了「跳过」。
  final bool confirmed;

  /// 输入框现值（未净化；净化与回退由宿主经控制器统一处理）。
  final SongSignature signature;
}
