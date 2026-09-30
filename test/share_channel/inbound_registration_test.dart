import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// 入站注册：清单上两条**独立**
/// intent-filter 与 `launchMode` —— Susume 出现在 `.susume` 文件的
/// 「用其他应用打开」里、不出现在无关文件的打开方式里，宿主测试只能
/// 断言注册声明本身；能否被系统匹配归真机验收。
XmlDocument _manifest() => XmlDocument.parse(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
    );

Iterable<XmlElement> _viewFilters(XmlDocument manifest) => manifest
    .findAllElements('intent-filter')
    .where(
      (f) => f.findAllElements('action').any(
            (a) => a.getAttribute('android:name') ==
                'android.intent.action.VIEW',
          ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('两条独立 VIEW filter：content+pathPattern 一条、显式 MIME 一条', () {
    final filters = _viewFilters(_manifest());
    expect(filters, hasLength(2), reason: '两条 filter 不合并（MIME 判据为空的 '
        'intent 匹配不上任何声明了 MIME 的 filter）');

    final schemeFilters = filters
        .where(
          (f) => f.findAllElements('data').any(
                (d) => d.getAttribute('android:scheme') == 'content',
              ),
        )
        .toList();
    expect(schemeFilters, hasLength(1));
    // 路径变体（`.*` 不跨「.」，故枚举中间点的条数）各自成一条 <data>：
    // 每条都必须是 scheme + host + pathPattern 三件同时声明（缺一则整组
    // 路径属性失效），且都不声明 MIME。
    final schemeData = schemeFilters.single.findAllElements('data').toList();
    expect(schemeData, isNotEmpty);
    for (final data in schemeData) {
      expect(data.getAttribute('android:scheme'), 'content');
      expect(data.getAttribute('android:host'), '*');
      expect(data.getAttribute('android:pathPattern'), endsWith(r'\.susume'));
      expect(
        data.getAttribute('android:mimeType'),
        isNull,
        reason: '这条 filter 不声明 MIME——MIME 判据为空的 intent 匹配不上 '
            '声明了 MIME 的 filter，合进一条会让 content 路径失效',
      );
    }

    final mimeFilters = filters
        .where(
          (f) => f.findAllElements('data').any(
                (d) => d.getAttribute('android:mimeType') != null,
              ),
        )
        .toList();
    expect(mimeFilters, hasLength(1));
    final mimeTypes = mimeFilters.single
        .findAllElements('data')
        .map((d) => d.getAttribute('android:mimeType'))
        .toList();
    expect(mimeTypes, contains('application/octet-stream'));
    expect(
      mimeTypes.where((m) => m == '*/*'),
      isEmpty,
      reason: '不声明裸 */*——无关文件的「打开方式」不被污染',
    );
  });

  test('launchMode = singleTask（热启动复用同一实例，不开第二个 Susume）', () {
    final activity = _manifest()
        .findAllElements('activity')
        .singleWhere((a) => a.getAttribute('android:name') == '.MainActivity');
    expect(activity.getAttribute('android:launchMode'), 'singleTask');
  });
}
