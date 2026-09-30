import 'package:dance_learning_app/help/help_documents.dart';

/// 帮助内容资产的仓库内路径：条目目录名与分组根目录都从装载模块的常量现算，
/// 测试与生产不会各自维护一份路径字面量。
const String helpGuideAssetDir = helpGuideAssetDirectory;
const String helpTutorialsAssetDir = helpTutorialsAssetDirectory;

/// 「下载视频」教程的条目目录（数字前缀定序；正文与图片都在其中）。
const String downloadVideoTutorialDirectory =
    '$helpTutorialsAssetDir/01-下载视频';

/// 「免费视频变清晰」教程的条目目录。
const String clearVideoTutorialDirectory =
    '$helpTutorialsAssetDir/02-免费视频变清晰';

/// 「问题反馈」教程的条目目录。
const String feedbackTutorialDirectory =
    '$helpTutorialsAssetDir/03-问题反馈';

/// 「已知的问题」教程的条目目录。
const String knownIssuesTutorialDirectory =
    '$helpTutorialsAssetDir/04-已知的问题';

/// 只有 `ui` 段的一副合法引导文案：假资产包喂它，装载就不走「文案解析失败」
/// 的降级分支（不测文案的套件共用）。
const String helpOnboardingStub = '''
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
