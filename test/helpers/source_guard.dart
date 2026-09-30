import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 读源码的结构护栏共用扫描件：两域模块护栏共用同一份
/// import 提取与「不读构建上下文、不碰容器」断言，沿既有源码扫描范式。
List<String> dartImportsOf(String path) => RegExp(
  '^import\\s+[\'"]([^\'"]+)[\'"]',
  multiLine: true,
).allMatches(File(path).readAsStringSync()).map((m) => m.group(1)!).toList();

/// 类体里的字段声明名（两空格缩进、字段名后接 `=` 或 `;`；取值器与方法不计；
/// 注释行不计）。函数型字段（形如 `bool Function(bool)? _drive;`）与无类型
/// 字段（`late final _drive;`）同样计入。
Set<String> declaredFieldNamesOf(String classBody) {
  final names = <String>{};
  for (final line in classBody.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    if (RegExp(r'\b(get|set)\b').hasMatch(line)) continue;
    final match =
        RegExp(_classField).firstMatch(line) ??
        RegExp(_typelessField).firstMatch(line);
    if (match != null) names.add(match.group(1)!);
  }
  return names;
}

/// 类体里的方法名与私有取值器名（两空格缩进；方法名后接 `(`，取值器写作
/// `T get _name`）。返回类型不限——可空基元、私有类型、记录类型都算，故
/// 「加一个方法」不会因返回类型的写法绕过清单。
Set<String> declaredMemberNamesOf(String classBody) {
  final names = <String>{};
  for (final line in classBody.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    // 类成员声明恰好两空格缩进：更深缩进是方法体与表达式续行，不计。
    if (!RegExp(r'^ {2}\S').hasMatch(line)) continue;
    final getter = RegExp(_classGetter).firstMatch(line);
    if (getter != null) {
      names.add(getter.group(1)!);
      continue;
    }
    if (RegExp(r'\b(get|set)\b').hasMatch(line)) continue;
    // 字段（含函数型与无类型字段）由 [declaredFieldNamesOf] 收；本函数只收
    // 「名字后直接跟 `(`」的方法签名。
    if (RegExp(_classField).hasMatch(line) ||
        RegExp(_typelessField).hasMatch(line)) {
      continue;
    }
    final rest = line.substring(2);
    final method = RegExp(r'(_\w+|build|initState|dispose)\s*\(').firstMatch(rest);
    if (method == null) continue;
    // 赋值右侧的调用不是声明。
    if (rest.substring(0, method.start).contains('=')) continue;
    names.add(method.group(1)!);
  }
  return names;
}

const _classField =
    r'^ {2}(?:late\s+final\s+|late\s+|final\s+|const\s+)?[A-Za-z_][\w<>,\.\?\(\)\[\]\{\} ]*?\s+(_[a-zA-Z]\w*)\s*(?:=[^=]|;)';
const _typelessField =
    r'^ {2}(?:late\s+final\s+|late\s+|final\s+|const\s+)(_[a-zA-Z]\w*)\s*(?:=[^=]|;)';
const _classGetter = r'^ {2}[\w<>,\.\?\[\]\{\} ]+ get (_\w+)';

/// 断言该模块源码不出现构建上下文、容器读取与页面 import。
void expectNoBuildContextOrHub(String path) {
  final source = codeOf(path);
  for (final forbidden in const [
    'player_page.dart',
    'package:flutter/material.dart',
    'package:flutter/widgets.dart',
    'BuildContext',
    'WidgetRef',
    'ref.watch',
    'ref.read',
  ]) {
    expect(
      source.contains(forbidden),
      isFalse,
      reason: '$path 不得出现 $forbidden',
    );
  }
}

/// 源码去掉注释行后的正文（`//` 起首的行不计）：结构断言只落代码，不被
/// 库头/行内注释里的词条满足（同 [expectNoDialogOrContextReads] 的口径）。
String codeOf(String path) =>
    File(path)
        .readAsStringSync()
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

/// 断言层域 widget 源码不弹对话框、不读构建上下文（`BuildContext` 只作
/// build 形参）：widget 自带子树，但编排面不经对话框与上下文读取。
///
/// 注释行不计入禁令（库头需要说明这条契约本身）。
void expectNoDialogOrContextReads(String path) {
  final code = codeOf(path);
  for (final forbidden in const [
    'showDialog',
    'Navigator.of',
    'MediaQuery',
  ]) {
    expect(code.contains(forbidden), isFalse, reason: '$path 不得出现 $forbidden');
  }
  final contextLines = code
      .split('\n')
      .where((line) => line.contains('BuildContext'))
      .toList();
  expect(contextLines.length, 1, reason: '$path 的构建上下文只作 build 形参');
  expect(
    contextLines.single.contains('Widget build('),
    isTrue,
    reason: '$path 的构建上下文只作 build 形参',
  );
}

/// [dir] 下命中 [matches] 的 dart 文件路径（[except] 排除自身）。扫描口径
/// 只有这一份实现：[libDartFilesWhere] 与需要扫 `test/` 的护栏都转调本
/// 函数，不各自写循环。
List<String> dartFilesUnder(
  String dir,
  bool Function(String source) matches, {
  String? except,
}) {
  final hits = <String>[];
  for (final entity in Directory(dir).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path == except) continue;
    if (matches(entity.readAsStringSync())) hits.add(entity.path);
  }
  return hits;
}

/// `lib/` 下源码命中 [matches] 的 dart 文件路径（[except] 排除自身）。给
/// 「某个事实只在唯一一处出现」这类断言共用（如「只有控制层构造轨道带输入」
/// 与「窗口控制器只被会话域 import」）。
List<String> libDartFilesWhere(
  bool Function(String source) matches, {
  String? except,
}) => dartFilesUnder('lib', matches, except: except);

/// 取源码里 [name] 那个类声明的源码段（至首个顶格 `}`）：让断言只落在这个
/// 类的字段与构造形参上，不被同文件其它类的同名形参满足。`class X extends Y`
/// 这类多行声明同样适用。
String classBodyOf(String source, String name) {
  final declaration = RegExp(
    '^(?:(?:abstract|sealed|interface|base|final)\\s+)*class\\s+$name\\b[^{]*\\{',
    multiLine: true,
  ).firstMatch(source);
  if (declaration == null) throw StateError('源码里没有 class $name');
  final end = source.indexOf('\n}\n', declaration.end);
  if (end < 0) throw StateError('class $name 的类体没有顶格结束括号');
  return source.substring(declaration.start, end);
}
