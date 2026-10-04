import 'dart:typed_data';

import 'package:dance_learning_app/help/help_platform_actions.dart';

/// 外部网址打开件的替身：记下交给它的每一条地址，按 [result] 回答「有没有
/// 真的交出去」。帮助域 widget 测试用它驱动「打开」与「打开失败走复制」两条
/// 分支，不碰真浏览器。
class FakeHelpExternalLinkOpener implements HelpExternalLinkOpener {
  FakeHelpExternalLinkOpener({this.result = true});

  /// 交出去是否成功；false 模拟设备上没有浏览器、系统拒绝等。
  bool result;

  /// 按交出顺序记下的地址。
  final List<String> opened = [];

  @override
  Future<bool> open(String href) async {
    opened.add(href);
    return result;
  }
}

/// 图片保存件的替身：记下交给它的每一份（字节、文件名），按 [failure] 决定
/// 是成功、权限被拒还是其它失败。帮助域 widget 测试用它断言「哪张资产的字节
/// 与文件名交了出去」并驱动三档提示，不碰真相册。
class FakeHelpImageSaver implements HelpImageSaver {
  FakeHelpImageSaver({this.failure});

  /// null = 成功；否则按这个异常失败。
  HelpImageSaveException? failure;

  /// 按保存顺序记下的文件名。
  final List<String> names = [];

  /// 按保存顺序记下的字节。
  final List<Uint8List> bytes = [];

  @override
  Future<void> save(Uint8List data, String name) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    bytes.add(data);
    names.add(name);
  }
}
