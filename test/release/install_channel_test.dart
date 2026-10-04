import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 正式版的安装身份：与 `test/release/android_identity_test.dart` 同一份事实，
/// 这里只用于断言流水线里的字面量。
const String installId = 'top.yurinka.susume';

/// 出包通道护栏（ADR-0003）：**正式版**与**测试版**各有各的流水线，两条都不许
/// 出成对方的身份。测试包只能由本机脚本或 `test-apk` 流水线出，且只归档产物
/// ——不进**更新源**、不进**下载页**、不碰**版本清单**。
///
/// 构建配置的行为没有 Dart 侧的可观察面，故按仓库既有的源码护栏范式扫流水线与
/// 脚本；真正的包名与签名由流水线里的 `aapt2` 断言与真机验收核对。
void main() {
  final release = File('.github/workflows/release.yml').readAsStringSync();
  final testApk = File('.github/workflows/test-apk.yml').readAsStringSync();
  final localScript = File('tool/build_test_apk.sh').readAsStringSync();

  group('发布流水线只出正式版', () {
    test('构建带 --flavor prod，且构建后断言产物就是正式身份', () {
      expect(release, contains('--flavor prod'));
      expect(release, isNot(contains('--flavor beta')), reason: '正式发布不许出测试版');
      expect(
        release,
        contains('"$installId"'),
        reason: '加了 flavor 之后「构建出哪个身份」由一个开关决定，必须断言',
      );
    });

    test('手动内测包那条同身份的路已拆掉', () {
      expect(release, isNot(contains('workflow_dispatch')));
      expect(
        release,
        isNot(contains('upload-artifact')),
        reason: '这条流水线只发版；归档是测试包那条流水线的事',
      );
    });
  });

  group('测试包流水线只出测试版', () {
    test('构建带 --flavor beta，并断言包名与 -test 版本名', () {
      expect(testApk, contains('--flavor beta'));
      expect(testApk, isNot(contains('--flavor prod')));
      expect(testApk, contains('$installId.test'));
      expect(testApk, contains('*-test)'), reason: '版本名要断言带 -test 身份标记');
    });

    test('只归档产物：不写更新源、不碰版本清单、不碰正式钥', () {
      expect(testApk, contains('upload-artifact'));
      expect(testApk, isNot(contains('latest.json')), reason: '测试包不进版本清单');
      expect(testApk, isNot(contains('aws s3')), reason: '测试包不写更新源');
      expect(
        testApk,
        isNot(contains('ANDROID_KEYSTORE_BASE64')),
        reason: '测试版用自己那把测试 keystore，正式钥不上这条流水线',
      );
      expect(testApk, contains('ANDROID_TEST_KEYSTORE_B64'));
    });
  });

  group('本机测试包脚本', () {
    test('带 flavor 与构建标识，凭据只读测试那一份', () {
      expect(localScript, contains('--flavor beta'));
      expect(localScript, contains('SUSUME_BUILD_ID'));
      expect(localScript, contains('android/key-test.properties'));
      expect(
        localScript,
        isNot(contains('key.properties')),
        reason: '本机出测试包不读正式凭据（`key-test.properties` 里没有这个子串）',
      );
    });
  });
}
