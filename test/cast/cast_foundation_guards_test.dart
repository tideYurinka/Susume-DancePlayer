import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// 投屏地基的声明面护栏：假接收端要**独立于本域的实现**（它是我们自己的
/// 对照，不是第二个客户端），以及**词表用词**（`lib/cast/CONTEXT.md` 的
/// _Avoid_ 那几条：投屏缓存不叫「渲染缓存」、断开投屏不叫「退出投屏」、副本里
/// 没有节拍动画）。
///
/// 这几条都是「仓库里的声明事实」；真电视认不认我们的 SOAP、真机上的读数与
/// 权限实况，归真机验收（步骤见 `lib/cast/docs/real-device-acceptance.md`）。
void main() {
  test('XML 文本转义只有一份实现（SOAP 信封那一处，DIDL 元数据复用它）', () {
    final hits = libDartFilesWhere(
      (source) => codeLinesOf(source).contains('&apos;'),
    );

    expect(
      hits,
      ['lib/cast/soap.dart'],
      reason: '信封与 DIDL-Lite 元数据共用 `escapeXmlText`，两处不许各写一遍',
    );
  });

  test('SSDP 的搜索目标不是可配项：`searchTarget` 全仓不再声明（M-SEARCH 报文逐字不变）', () {
    final hits = libDartFilesWhere(
      (source) => codeLinesOf(source).contains('searchTarget'),
    );

    expect(
      hits,
      isEmpty,
      reason: '搜索目标恒是 kMediaRendererSearchTarget：没有第二个取值，就没有第二个入参',
    );
  });

  test('假接收端不 import 本域：它是独立对照，不是第二个客户端', () {
    final imports = dartImportsOf('tool/cast_fake_receiver.dart');

    expect(imports, isNotEmpty, reason: '扫描不到 import，护栏自身已失效');
    expect(
      imports.where(
        (import) => import.startsWith('package:dance_learning_app/cast/'),
      ),
      isEmpty,
      reason: '假接收端一旦复用本域的报文装配，端到端就不再是独立对照',
    );
  });

  test('投屏缓存不写成避用叫法「渲染缓存」', () {
    // 词表（`lib/cast/CONTEXT.md` 的「投屏缓存」）：避开「渲染缓存」——省掉
    // 「投屏」会与封面取帧一类本机缓存混指。
    final source = File('lib/cast/cast_render_cache.dart').readAsStringSync();

    expect(
      source.contains('渲染缓存'),
      isFalse,
      reason: '这一处说「投屏缓存 / 投屏缓存区」（词表的 _Avoid_）',
    );
    expect(source.contains('投屏缓存'), isTrue, reason: '护栏自身要扫到文件内容');
  });

  test('断开投屏不写成避用叫法「退出投屏」', () {
    // 词表（「断开投屏」）：_Avoid_ 是「退出投屏」——它会与「退出投屏态」这一
    // 模式动作读成两件事，而本项目里它们是同一次。
    for (final path in const [
      'lib/player/cast_run.dart',
      'lib/player_session/player_session.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(
        source.contains('退出投屏'),
        isFalse,
        reason: '$path：这个动作叫「断开投屏」，离开模式态叫「离开投屏态」',
      );
    }
  });

  test('ADR-0004 不说投屏副本里有节拍动画', () {
    // 词表（「投屏副本」）：呈现类只烤**逐拍静态数字**，摆锤与动画一像素都不
    // 进副本——ADR 里那两句旧措辞（决定段与 Consequences）与词表、与实现打脸。
    final adr = File('docs/adr/0004-cast-render-not-mirror.md').readAsStringSync();

    expect(
      adr.contains('数拍与节拍动画'),
      isFalse,
      reason: '决定段不得把节拍动画列进副本的内容',
    );
    expect(
      adr.contains('数拍数字与节拍动画'),
      isFalse,
      reason: 'Consequences 不得说副本里的动画会与手机上那份不一致',
    );
  });
}
