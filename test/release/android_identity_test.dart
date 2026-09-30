import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/source_guard.dart';

/// 安装身份护栏：装出去的 Susume 在
/// 系统里只有一个定死的安装身份，仓库里写死它的每一处都必须与之一致，Kotlin
/// 的 package 声明也不得与所在目录自相矛盾。宿主测试只断言仓库里的声明事实；
/// 包在系统里实际叫什么、能不能 force-stop 与 run-as，归真机验收。
const installId = 'top.yurinka.susume';
const templateInstallId = 'com.example.dance_learning_app';

/// 身份面上参与文本扫描的扩展名（图标等二进制资源不读）。
const _textExtensions = ['.kt', '.kts', '.xml', '.java', '.cpp', '.sh', '.md'];

Iterable<String> _textFilesUnder(String dir) sync* {
  for (final entity in Directory(dir).listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!_textExtensions.any(entity.path.endsWith)) continue;
    yield entity.path;
  }
}

/// 会写死安装身份的仓库面：Android 源码与清单、Gradle 配置、文档。
Iterable<String> _identitySurfaces() sync* {
  yield* _textFilesUnder('android/app/src');
  yield* _textFilesUnder('docs');
  yield* const [
    'android/app/build.gradle.kts',
    'android/build.gradle.kts',
    'android/settings.gradle.kts',
    'android/gradle.properties',
  ];
}

void main() {
  test('Gradle 的 namespace 与 applicationId 都是定死的安装身份', () {
    final gradle = codeOf('android/app/build.gradle.kts');
    expect(gradle, contains('namespace = "$installId"'));
    expect(gradle, contains('applicationId = "$installId"'));
  });

  test('Kotlin 源码的 package 声明与所在目录一致', () {
    final sources = _textFilesUnder(
      'android/app/src/main/kotlin',
    ).where((path) => path.endsWith('.kt')).toList();
    expect(sources, isNotEmpty, reason: '扫描不到 Kotlin 源码，护栏自身已失效');

    for (final path in sources) {
      final declared = RegExp(
        r'^package\s+(\S+)\s*$',
        multiLine: true,
      ).firstMatch(codeOf(path))!.group(1)!;
      expect(declared, installId, reason: '$path 的 package 声明不是定死的安装身份');
      expect(
        p.dirname(path).replaceAll(r'\', '/'),
        endsWith(declared.replaceAll('.', '/')),
        reason: '$path 的 package 声明与目录自相矛盾',
      );
    }
  });

  test('主 manifest 的用户可见应用名仍是 Susume', () {
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:label="Susume"'),
    );
  });

  test('身份面上没有模板占位包名的残留', () {
    final surfaces = _identitySurfaces().toList();
    expect(surfaces, isNotEmpty, reason: '扫描不到任何身份面，护栏自身已失效');
    for (final path in surfaces) {
      expect(
        codeOf(path),
        isNot(contains(templateInstallId)),
        reason: '$path 仍引用模板占位包名',
      );
    }
  });

  test('Dart 包名未改', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('name: dance_learning_app'),
    );
  });
}
