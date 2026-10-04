import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// Release 构建的签名接法与版本号口径。
///
/// 构建配置没有 Dart 侧的可观察行为，按仓库既有源码护栏范式扫
/// `android/` 的构建脚本与忽略清单：签名来源、回落路径与 versionCode 的
/// 唯一真源都在这里定死，真正的签名结果由 acceptance 用 apksigner 核对。
///
/// 三份**安装身份**（ADR-0003）带来的新纪律是本文件的重点：**用哪把钥只由
/// flavor 决定**。构建类型的 `signingConfig` 优先级高于 flavor，写在构建类型上
/// 会把测试版悄悄签成正式钥——Gradle 不报错，只有 `:app:signingReport` 看得见。
void main() {
  final gradle = codeOf('android/app/build.gradle.kts');
  final gitignore = File('android/.gitignore').readAsStringSync();

  group('签名来源', () {
    test('正式签名读 key.properties 的 release 配置，缺文件时回落到 debug', () {
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

    test('用哪把钥只由 flavor 决定：构建类型上不许写 signingConfig', () {
      final buildTypes = RegExp(
        r'buildTypes \{(.*?)\n    \}',
        dotAll: true,
      ).firstMatch(gradle)?.group(1);
      expect(buildTypes, isNotNull, reason: 'Gradle 侧应有 buildTypes 块');
      expect(
        RegExp(r'signingConfig\s*=').hasMatch(buildTypes!),
        isFalse,
        reason: '构建类型的签名优先级高于 flavor，写在这里会把测试版签成别的钥',
      );
      expect(
        gradle,
        contains('signingConfig = signingConfigs.getByName("test")'),
        reason: '测试版的钥由 beta flavor 指到测试那一套',
      );
    });

    test('测试签名读 key-test.properties，缺文件时不回落', () {
      expect(
        gradle,
        contains('rootProject.file("key-test.properties")'),
        reason: '测试签名从 android/key-test.properties 读',
      );
      for (final key in const [
        'keyAlias',
        'keyPassword',
        'storeFile',
        'storePassword',
      ]) {
        expect(
          gradle,
          contains('testKeystoreProperties.getProperty("$key")'),
          reason: '$key 从 key-test.properties 读',
        );
      }
      expect(
        gradle,
        contains('requireTestSigning'),
        reason: '缺测试钥要在测试版的打包路径上直接失败，不靠 AGP 兜底',
      );
      expect(gradle, contains('tasks.matching'), reason: '这道前置检查只挂在测试版的打包任务上');
    });

    test('正式签名四项都取自 key.properties，没有第二处凭据字面量', () {
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
    test('两套凭据与 keystore 都在 android/.gitignore 忽略清单里', () {
      expect(gitignore, contains('key.properties'));
      expect(
        gitignore,
        contains('key-test.properties'),
        reason: '测试版那把钥的凭据同样不许入库',
      );
      expect(gitignore, contains('*.jks'));
      expect(gitignore, contains('*.keystore'));
    });
  });
}
