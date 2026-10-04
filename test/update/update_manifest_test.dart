import 'package:dance_learning_app/update/update_check.dart';
import 'package:dance_learning_app/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/update_manifest_fixture.dart';

/// 版本清单解析与版本判定：
/// 把"任何字段缺失或类型不对"都收敛为"无更新"，不抛异常、不弹错误；判断有
/// 无新版本的唯一依据是 `build_number` 与本机构建号的大小。
void main() {
  group('清单解析', () {
    test('五个字段齐备且合法：原样读出', () {
      final manifest = UpdateManifest.parse(updateManifestJson());

      expect(manifest, isNotNull);
      expect(manifest!.buildNumber, 1);
      expect(manifest.versionName, '0.1.0');
      expect(manifest.size, 81234567);
      expect(manifest.apkUrl, updateManifestFixtureApkUrl);
      expect(manifest.notes, '首次内测。');
    });

    test('更新说明为空串：合法（允许为空），不是"缺字段"', () {
      final manifest = UpdateManifest.parse(
        updateManifestJson({...updateManifestJsonFields(), 'notes': ''}),
      );

      expect(manifest, isNotNull);
      expect(manifest!.notes, isEmpty);
    });

    test('整份不是 JSON：收敛为无更新', () {
      expect(UpdateManifest.parse('这不是 JSON'), isNull);
    });

    test('顶层不是对象：收敛为无更新', () {
      expect(UpdateManifest.parse('[1, 2, 3]'), isNull);
    });

    test('build_number 缺失：收敛为无更新', () {
      final fields = updateManifestJsonFields()..remove('build_number');
      expect(UpdateManifest.parse(updateManifestJson(fields)), isNull);
    });

    test('build_number 是字符串：收敛为无更新', () {
      expect(
        UpdateManifest.parse(
          updateManifestJson({
            ...updateManifestJsonFields(),
            'build_number': '1',
          }),
        ),
        isNull,
      );
    });

    test('build_number 为负：收敛为无更新', () {
      expect(
        UpdateManifest.parse(
          updateManifestJson({
            ...updateManifestJsonFields(),
            'build_number': -1,
          }),
        ),
        isNull,
      );
    });

    test('version_name 为空串：收敛为无更新', () {
      expect(
        UpdateManifest.parse(
          updateManifestJson({
            ...updateManifestJsonFields(),
            'version_name': '',
          }),
        ),
        isNull,
      );
    });

    test('size 不是数字：收敛为无更新', () {
      expect(
        UpdateManifest.parse(
          updateManifestJson({
            ...updateManifestJsonFields(),
            'size': '77.5 MB',
          }),
        ),
        isNull,
      );
    });

    test('apk_url 为空串：收敛为无更新', () {
      expect(
        UpdateManifest.parse(
          updateManifestJson({...updateManifestJsonFields(), 'apk_url': ''}),
        ),
        isNull,
      );
    });

    test('notes 缺失：收敛为无更新', () {
      final fields = updateManifestJsonFields()..remove('notes');
      expect(UpdateManifest.parse(updateManifestJson(fields)), isNull);
    });
  });

  group('版本判定', () {
    test('远端构建号更大：有新版本', () {
      expect(
        hasUpdate(
          manifest: updateManifestFixture(buildNumber: 2),
          localBuildNumber: 1,
        ),
        isTrue,
      );
    });

    test('远端构建号相等：无新版', () {
      expect(
        hasUpdate(
          manifest: updateManifestFixture(buildNumber: 1),
          localBuildNumber: 1,
        ),
        isFalse,
      );
    });

    test('远端构建号更小：无新版', () {
      expect(
        hasUpdate(
          manifest: updateManifestFixture(buildNumber: 1),
          localBuildNumber: 2,
        ),
        isFalse,
      );
    });

    test('取不到清单：无新版', () {
      expect(hasUpdate(manifest: null, localBuildNumber: 1), isFalse);
    });

    test('本机构建号读不出：无新版', () {
      expect(
        hasUpdate(
          manifest: updateManifestFixture(buildNumber: 99),
          localBuildNumber: null,
        ),
        isFalse,
      );
    });
  });
}
