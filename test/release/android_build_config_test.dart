import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// Release 构建的签名接法与版本号口径。
///
/// 构建配置没有 Dart 侧的可观察行为，按仓库既有源码护栏范式扫
/// `android/` 的构建脚本与忽略清单：签名来源、回落路径与 versionCode 的
/// 唯一真源都在这里定死，真正的签名结果由 acceptance 用 apksigner 核对。
void main() {
  final gradle = codeOf('android/app/build.gradle.kts');
  final gitignore = File('android/.gitignore').readAsStringSync();

  group('签名来源', () {
    test('release 用 key.properties 里的 release 配置，缺文件时回落到 debug', () {
      expect(
        gradle,
        contains('rootProject.file("key.properties")'),
        reason: '签名配置从 android/key.properties 读',
      );
      expect(
        gradle,
        contains('if (hasReleaseSigning)'),
        reason: '有没有签名配置决定用哪套签名',
      );
      expect(gradle, contains('signingConfigs.getByName("release")'));
      expect(gradle, contains('signingConfigs.getByName("debug")'));
    });

    test('release 签名四项都取自 key.properties，没有第二处凭据字面量', () {
      for (final key in const [
        'keyAlias',
        'keyPassword',
        'storeFile',
        'storePassword',
      ]) {
        expect(
          gradle,
          contains('keystoreProperties.getProperty("$key")'),
          reason: '$key 从 key.properties 读',
        );
      }
    });
  });

  group('不开 R8/minify', () {
    test('release 构建类型没有打开 minify / shrinkResources', () {
      final releaseBuildType = RegExp(
        r'buildTypes \{(.*?)\n    \}',
        dotAll: true,
      ).firstMatch(gradle)?.group(1);
      expect(releaseBuildType, isNotNull, reason: 'Gradle 侧应有 buildTypes 块');
      expect(releaseBuildType, contains('release {'));
      expect(
        RegExp(r'isMinifyEnabled\s*=\s*true').hasMatch(releaseBuildType!),
        isFalse,
        reason: '流水线不开 R8/minify',
      );
      expect(
        RegExp(r'isShrinkResources\s*=\s*true').hasMatch(releaseBuildType),
        isFalse,
        reason: '流水线不开 shrinkResources',
      );
    });
  });

  group('版本号真源', () {
    test('versionCode 与 versionName 只来自 pubspec.yaml，Gradle 侧无字面量', () {
      expect(gradle, contains('versionCode = flutter.versionCode'));
      expect(gradle, contains('versionName = flutter.versionName'));
      expect(
        RegExp(r'versionCode\s*=\s*\d').hasMatch(gradle),
        isFalse,
        reason: 'Gradle 侧不新增第二处 versionCode 字面量',
      );
    });
  });

  group('不入库', () {
    test('key.properties 与 keystore 都在 android/.gitignore 忽略清单里', () {
      expect(gitignore, contains('key.properties'));
      expect(gitignore, contains('*.jks'));
      expect(gitignore, contains('*.keystore'));
    });
  });
}
