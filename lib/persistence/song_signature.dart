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

/// 文件名回落名（「歌曲署名」的回落规则，见 `lib/annotation/CONTEXT.md`
/// 词条）：把文件名当**名字**用时取的名字——去掉最后一个 `.` 及其之后，
/// 当且仅当该点不在开头且后面非空。不查扩展名白名单、不改大小写、不替换
/// 非法字符（`a.b.mp4 → a.b`、`dance → dance`、`.mp4 → .mp4`、
/// `.hidden.mp4 → .hidden`、`DANCE.MP4 → DANCE`、`dance. → dance.`）。
///
/// **本仓唯一一处「把文件名当名字用」的去扩展名点**：名字的世界的读面都过它
/// （见 [danceDisplayTitle]）。文件的世界另有自己的截法、不吃这条规则——快速键
/// 与私有副本取唯一名照吃原始文件名；两处**文件的名字**自带一套截法并有意
/// 留在原处：`lib/help/platform_help_actions.dart` 交给相册 API 的 `name` 入参
/// （相册按字节探测格式自己补扩展名）、`lib/persistence/document_quarantine.dart`
/// 的旁路留档文件名（改这条规则会改动盘上文件名）。第四处去扩展名一冒出来即
/// 触发 `test/architecture/naming_fallback_test.dart` 的护栏。
String songFallbackName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return fileName;
  return fileName.substring(0, dot);
}

/// 署名显示串（渲染层拼接）：`「版本舞者」歌曲名 -
/// 版本注记`；空版本舞者/空注记省略对应部分；[signature] 为 null 或
/// 歌曲名为空（未署名）时回退 [fallback]——回退串由调用方给，本函数不认它是
/// 什么：把文件名当**名字**用的读面给 [danceDisplayTitle] 取好的「文件名回落
/// 名」（不是原始文件名）。
String signatureDisplayText(SongSignature? signature, String fallback) {
  if (signature == null || signature.song.isEmpty) return fallback;
  final dancer = signature.dancer.isEmpty ? '' : '「${signature.dancer}」';
  final remark = signature.remark.isEmpty ? '' : ' - ${signature.remark}';
  return '$dancer${signature.song}$remark';
}

/// 舞的显示标题：署名显示串 [signatureDisplayText] 优先，未署名（[signature]
/// 为 null 或歌曲名为空）回落[文件名回落名][songFallbackName]（去扩展名的
/// [fileName]）——**这一组合只有本处一份实现**，舞库卡片与舞页标题、组员方案
/// 导入的舞标题、系统通知的名字表同调它（票 #12 的「与舞库卡片同源」，由
/// `test/architecture/naming_fallback_test.dart` 钉住）。分享包名（`susumePackageFileName`，
/// `lib/package/susume_package.dart`）另走一步——名字后面还要接 `.susume`、再去非法
/// 字符——但回落同样只经 [songFallbackName]；别的回退串（如统计页的视频标识）各走
/// 各的 [signatureDisplayText]，不混进这里。
String danceDisplayTitle(SongSignature? signature, String fileName) =>
    signatureDisplayText(signature, songFallbackName(fileName));
