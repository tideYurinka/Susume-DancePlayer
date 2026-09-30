import 'package:dance_learning_app/help/help_documents.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_help_asset_bundle.dart';

/// 帮助中心目录改扫文件夹：输入侧是可注入的假
/// 资产包，输出侧是内容 provider 的载荷。断言只落在**可观察的装载结果**上——
/// 两组条目、顺序、标题、一句说明与缺内容时的降级。
void main() {
  const guide = 'assets/help/guide';
  const tutorials = 'assets/help/tutorials';

  /// 只有 `ui` 段的一副合法引导文案（本套件不测文案）。
  const onboarding = '''
units: {}
steps: {}
ui:
  next: 下一步
  skip: 跳过
  guide_units_title: 新手引导
  reset_all: 重置所有教程
  reset_dialog_title: 重置所有教程？
  reset_dialog_body: 正文
  reset_dialog_cancel: 取消
  reset_dialog_confirm: 重置
''';

  test('两组条目由扫到的目录现算：顺序取数字前缀，标题取一级标题', () async {
    final content = await loadHelpContent(
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: onboarding,
        '$guide/02-播放与手势/播放与手势.md': '# 播放与手势\n\n播放控制与手势。\n',
        '$guide/01-导入与舞库/导入与舞库.md': '# 导入与舞库\n\n导入与管理。\n',
        '$tutorials/02-免费视频变清晰/用电脑将视频变清晰.md':
            '# 用电脑将视频变清晰\n\n把视频变清晰。\n',
        '$tutorials/01-下载视频/下载视频.md': '# 下载视频\n\n先存到相册。\n',
      }),
    );

    expect(
      content.manualChapters.map((d) => d.id).toList(),
      ['导入与舞库', '播放与手势'],
      reason: '顺序取目录名的数字前缀，不按枚举次序',
    );
    expect(
      content.tutorials.map((d) => d.id).toList(),
      ['下载视频', '免费视频变清晰'],
    );
    expect(content.manualChapters.first.displayTitle, '导入与舞库');
    expect(content.tutorials.first.displayTitle, '下载视频');
  });

  test('列表页的一句说明取标题之后的第一段；正文引用的图仍收进 imageAssets', () async {
    const directory = '$tutorials/01-下载视频';
    final content = await loadHelpContent(
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: onboarding,
        '$directory/下载视频.md':
            '# 下载视频\n\n把舞蹈视频存到相册。\n\n## 方法一\n\n![截图](shot.png)\n',
      }, binary: {
        '$directory/shot.png': onePixelPng,
      }),
    );

    final entry = content.document('下载视频')!;
    expect(entry.listDescription, '把舞蹈视频存到相册。');
    expect(entry.imageAssets, contains('$directory/shot.png'));
  });

  test('列表页的一句说明只认正文级段落：引用块里的提示不算', () async {
    final content = await loadHelpContent(
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: onboarding,
        '$tutorials/01-下载视频/下载视频.md':
            '# 下载视频\n\n> 使用某开源软件\n\n把舞蹈视频存到相册。\n',
      }),
    );

    final entry = content.document('下载视频')!;
    expect(
      entry.listDescription,
      '把舞蹈视频存到相册。',
      reason: '引用块里的提示不是「一级标题之后的第一段」',
    );
  });

  test('一级标题之前有段落：那句说明仍留空（只取标题之后的第一段）', () async {
    final content = await loadHelpContent(
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: onboarding,
        '$tutorials/01-下载视频/下载视频.md': '标题之前的开场白。\n\n# 下载视频\n',
      }),
    );

    final entry = content.document('下载视频')!;
    expect(entry.displayTitle, '下载视频');
    expect(entry.listDescription, isNull);
  });

  test('条目目录缺正文：仍出现在列表里，标题取目录名、说明留空', () async {
    final content = await loadHelpContent(
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: onboarding,
      }, binary: {
        // 目录里只有一张图、没有 Markdown。
        '$tutorials/01-下载视频/shot.png': onePixelPng,
      }),
    );

    final entry = content.document('下载视频');
    expect(entry, isNotNull, reason: '缺正文的条目仍在列表里');
    expect(entry!.displayTitle, '下载视频', reason: '标题退回目录名');
    expect(entry.listDescription, isNull, reason: '说明留空');
  });

  test('正文无一级标题：标题退回目录名、说明留空，正文照常可读', () async {
    final content = await loadHelpContent(
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: onboarding,
        '$tutorials/01-下载视频/下载视频.md': '## 只有二级\n\n一段正文。\n',
      }),
    );

    final entry = content.document('下载视频')!;
    expect(entry.displayTitle, '下载视频');
    expect(entry.listDescription, isNull);
    expect(entry.markdown, contains('一段正文。'));
  });

  test('正文引用的图片不在盘上：不收进 imageAssets，其余照常', () async {
    final content = await loadHelpContent(
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: onboarding,
        '$tutorials/01-下载视频/下载视频.md': '# 下载视频\n\n说明。\n\n![缺图](missing.png)\n',
      }),
    );

    final entry = content.document('下载视频')!;
    expect(entry.imageAssets, isEmpty);
    expect(entry.listDescription, '说明。');
  });

  test('未登记图标的条目 id：照常装载出行，不崩', () async {
    final content = await loadHelpContent(
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: onboarding,
        '$guide/08-未来新章/未来新章.md': '# 未来新章\n\n新加一章。\n',
      }),
    );

    final entry = content.document('未来新章');
    expect(entry, isNotNull, reason: '新加条目不登记图标也照常出现在列表里');
    expect(entry!.displayTitle, '未来新章');
    // 装载结果里不再有「列表缩略图」这一项；行图标由页面按 id 查表取得。
    expect(entry.listDescription, '新加一章。');
  });

  test('按 id 查条目：两个分组合起来查得到，找不到为 null', () async {
    final content = await loadHelpContent(
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: onboarding,
        '$guide/01-导入与舞库/导入与舞库.md': '# 导入与舞库\n\n导入。\n',
        '$tutorials/01-下载视频/下载视频.md': '# 下载视频\n\n下载。\n',
      }),
    );

    expect(content.document('导入与舞库')?.displayTitle, '导入与舞库');
    expect(content.document('下载视频')?.displayTitle, '下载视频');
    expect(content.document('不存在'), isNull);
  });
}
