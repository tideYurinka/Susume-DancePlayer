/// 歌曲署名（`lib/annotation/CONTEXT.md` 词条「歌曲署名」，字段归属）。
///
/// 每段视频一个署名三元组：可选版本舞者 + 歌曲名 + 可选版本注记。
/// **结构存储、绝不存拼接串**：显示串 `「版本舞者」歌曲名 - 版本注记`
/// 由渲染层拼接（空版本舞者/空注记省略对应部分），本模块不做任何
/// 显示串的解析或拼接。
///
/// 归属：随公开标记文件（`markers_<hash>.json` 的 `signature` 段）分享；
/// 标记文件未创建前以索引条目的署名缓存承载（`index.json` 的
/// `signatureCache`，见 `persistence/video_index.dart`）。
class SongSignature {
  const SongSignature({this.dancer = '', this.song = '', this.remark = ''});

  /// 可选版本舞者（如「如」），空串表示无。
  final String dancer;

  final String song;

  /// 可选版本注记（如「9人版」），空串表示无。
  final String remark;

  Map<String, dynamic> toJson() => {
    'dancer': dancer,
    'song': song,
    'remark': remark,
  };

  /// 结构读取；缺字段按空串兜底（旧文件/部分写入不崩）。
  factory SongSignature.fromJson(Map<String, dynamic> json) {
    return SongSignature(
      dancer: json['dancer'] as String? ?? '',
      song: json['song'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SongSignature &&
        other.dancer == dancer &&
        other.song == song &&
        other.remark == remark;
  }

  @override
  int get hashCode => Object.hash(dancer, song, remark);

  @override
  String toString() =>
      'SongSignature(dancer: $dancer, song: $song, remark: $remark)';
}

/// 署名净化：去各字段首尾空白、剥离控制字符
/// （C0 U+0000–U+001F 与 DEL U+007F，含换行）；歌曲名净化后为空时
/// 回退 [fallbackSong]（同名净化，如导入/改名框按文件名署名的场景）。
SongSignature sanitizeSignature(
  SongSignature raw, {
  required String fallbackSong,
}) {
  String clean(String value) {
    final buffer = StringBuffer();
    for (final code in value.codeUnits) {
      if (code > 0x1f && code != 0x7f) buffer.writeCharCode(code);
    }
    return buffer.toString().trim();
  }

  final song = clean(raw.song);
  return SongSignature(
    dancer: clean(raw.dancer),
    song: song.isNotEmpty ? song : clean(fallbackSong),
    remark: clean(raw.remark),
  );
}

/// 署名显示串（渲染层拼接）：`「版本舞者」歌曲名 -
/// 版本注记`；空版本舞者/空注记省略对应部分；[signature] 为 null 或
/// 歌曲名为空（未署名）时回退 [fallback]（文件名）。
String signatureDisplayText(SongSignature? signature, String fallback) {
  if (signature == null || signature.song.isEmpty) return fallback;
  final dancer = signature.dancer.isEmpty ? '' : '「${signature.dancer}」';
  final remark = signature.remark.isEmpty ? '' : ' - ${signature.remark}';
  return '$dancer${signature.song}$remark';
}
