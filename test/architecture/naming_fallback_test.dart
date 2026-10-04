import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// 「文件名回落名」的口径护栏（见 `lib/annotation/CONTEXT.md` 词条「歌曲署名」）：
///
/// - **组合只有一处**：署名显示串 `signatureDisplayText` 与文件名回落名
///   `songFallbackName` 的拼接是一组读数面（舞库卡片与舞页标题、组员方案
///   导入的舞标题、系统通知的名字表、分享包名）共用的同一条规则，只许住在
///   署名模块的 `danceDisplayTitle` 里——各读面各抄一份就红（票 #12 的验收
///   点：与舞库卡片仍同源）。
/// - **去扩展名的实现点只有三处**：一处是名字的世界的规则
///   （`songFallbackName`），另两处是文件的世界各自的截法——交给相册 API 的
///   `name` 入参（`lib/help/platform_help_actions.dart`）、旁路留档文件名
///   （`lib/persistence/document_quarantine.dart`）。冒出第四处就红：要么改调
///   纯件，要么在本护栏与 `songFallbackName` 的文档注释里登记豁免、说明它
///   为什么是「文件的名字」。
void main() {
  test('署名显示串 + 文件名回落名 的组合只住署名模块一处', () {
    final hits = libDartFilesWhere((source) {
      final code = codeLinesOf(source);
      return code.contains('signatureDisplayText') &&
          code.contains('songFallbackName');
    })..sort();

    expect(hits, [
      'lib/persistence/song_signature.dart',
    ], reason: '组合规则被抄成了第二份：$hits（读面应调 danceDisplayTitle）');
  });

  test('去扩展名的实现点：名字的世界一处规则 + 文件的世界两处豁免', () {
    final hits = libDartFilesWhere((source) {
      final code = codeLinesOf(source);
      return code.contains("lastIndexOf('.')") ||
          code.contains('basenameWithoutExtension');
    })..sort();

    expect(hits, [
      'lib/help/platform_help_actions.dart',
      'lib/persistence/document_quarantine.dart',
      'lib/persistence/song_signature.dart',
    ], reason: '冒出第四处去扩展名：$hits（改调 songFallbackName，或在护栏与文档注释里登记豁免）');
  });
}
