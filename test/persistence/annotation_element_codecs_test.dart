import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';

/// 标注元素类型自带编解码：
/// 分段线 / 半拍线 / 局部镜像片段各自声明字段与读写，外层文档只做
/// 「一组元素 ↔ 一个 JSON 数组」。验收：文件形状逐位不变 + 元素级
/// 往返保真 + 元素层未知键保底。
void main() {
  group('SegmentLine：元素级编解码', () {
    test('toJson/fromJson 往返保真（含 flag）', () {
      const line = SegmentLine(
        position: Duration(milliseconds: 12345),
        flagged: true,
      );
      final restored = SegmentLine.fromJson(line.toJson());
      expect(restored, line);
    });

    test('键名与既有文件形状逐位一致', () {
      const line = SegmentLine(position: Duration(milliseconds: 100));
      expect(line.toJson(), {'timeMs': 100, 'flag': false});
    });

    test('flag 缺省读为 false；timeMs 非法条目丢弃', () {
      expect(SegmentLine.fromJson({'timeMs': 7}), const SegmentLine(
        position: Duration(milliseconds: 7),
      ));
      expect(SegmentLine.fromJson('bad'), isNull);
      expect(SegmentLine.fromJson({'timeMs': 1.5}), isNull);
      expect(SegmentLine.fromJson({'flag': true}), isNull);
    });

    test('fromJsonList 跳过损坏条目、保留合法项', () {
      expect(
        SegmentLine.fromJsonList([
          'bad',
          42,
          {'timeMs': 1.5},
          {'timeMs': 2500, 'flag': true},
        ]),
        const [SegmentLine(position: Duration(milliseconds: 2500), flagged: true)],
      );
    });

    test('元素层未知键原样带回、写回保留且不覆盖已登记字段', () {
      final restored = SegmentLine.fromJson({
        'timeMs': 100,
        'flag': true,
        'futureField': {'a': 1},
      });
      expect(restored, const SegmentLine(
        position: Duration(milliseconds: 100),
        flagged: true,
      ));
      final written = restored!.toJson();
      expect(written['futureField'], {'a': 1});
      expect(written['timeMs'], 100);
      expect(written['flag'], isTrue);
    });

    test('未知键不参与相等比较', () {
      final a = SegmentLine.fromJson({'timeMs': 100, 'x': 1});
      final b = SegmentLine.fromJson({'timeMs': 100, 'x': 2});
      expect(a, b);
    });
  });

  group('HalfBeatLine：元素级编解码', () {
    test('往返保真；键名与既有文件形状逐位一致', () {
      const line = HalfBeatLine(position: Duration(milliseconds: 2500));
      expect(line.toJson(), {'timeMs': 2500});
      expect(HalfBeatLine.fromJson(line.toJson()), line);
    });

    test('timeMs 非法条目丢弃；损坏列表条目跳过', () {
      expect(HalfBeatLine.fromJson({'timeMs': 2.5}), isNull);
      expect(
        HalfBeatLine.fromJsonList(['bad', {'timeMs': 3}]),
        const [HalfBeatLine(position: Duration(milliseconds: 3))],
      );
    });

    test('元素层未知键原样带回并写回', () {
      final restored = HalfBeatLine.fromJson({'timeMs': 9, 'p1': 'x'});
      expect(restored!.toJson(), {'p1': 'x', 'timeMs': 9});
    });
  });

  group('LocalMirrorFragment：元素级编解码', () {
    test('往返保真；键名与既有文件形状逐位一致', () {
      const fragment = LocalMirrorFragment(
        startMs: 1000,
        endMs: 8000,
      );
      expect(fragment.toJson(), {
        'startMs': 1000,
        'endMs': 8000,
      });
      expect(LocalMirrorFragment.fromJson(fragment.toJson()), fragment);
    });

    test('v2 遗留 enabled 键不解释、只留保底区；startMs/endMs 非法条目丢弃', () {
      final withLegacy = LocalMirrorFragment.fromJson({
        'startMs': 1,
        'endMs': 2,
        'enabled': false,
      });
      expect(withLegacy, const LocalMirrorFragment(startMs: 1, endMs: 2),
          reason: 'enabled 不再被解释');
      expect(withLegacy!.toJson()['enabled'], isFalse,
          reason: '遗留键走保底区写回原样（既有透传政策）');
      expect(LocalMirrorFragment.fromJson({'startMs': 1}), isNull);
      expect(LocalMirrorFragment.fromJson({'endMs': 2}), isNull);
      expect(LocalMirrorFragment.fromJson({'startMs': 2.5, 'endMs': 3}), isNull);
    });

    test('fromJsonList 跳过损坏条目、保留合法项', () {
      expect(
        LocalMirrorFragment.fromJsonList([
          'bad',
          {'startMs': 1},
          {'startMs': 10, 'endMs': 20},
        ]),
        const [LocalMirrorFragment(startMs: 10, endMs: 20)],
      );
    });

    test('元素层未知键原样带回、写回保留且不覆盖已登记字段', () {
      final restored = LocalMirrorFragment.fromJson({
        'startMs': 10,
        'endMs': 20,
        'enabled': true,
        'future': [1, 2],
      });
      final written = restored!.toJson();
      expect(written['future'], [1, 2]);
      expect(written['startMs'], 10);
      expect(written['endMs'], 20);
      expect(written['enabled'], isTrue);
    });
  });

  group('MarkersDocument：外层只做「元素表 ↔ JSON 数组」', () {
    test('元素层未知键经文档级往返仍保留（三类元素）', () {
      final doc = MarkersDocument.fromJson({
        'version': 8,
        'annotations': {
          'segmentLines': [
            {'timeMs': 100, 'flag': false, 'segFuture': 1},
          ],
          'halfBeatLines': [
            {'timeMs': 200, 'hbFuture': 'y'},
          ],
          'localMirrorFragments': [
            {'startMs': 300, 'endMs': 400, 'lmFuture': null},
          ],
        },
      });
      final written = doc.toJson();
      final ann = written['annotations'] as Map;
      final seg = (ann['segmentLines'] as List).single;
      final hb = (ann['halfBeatLines'] as List).single;
      final lm = (ann['localMirrorFragments'] as List).single;
      expect(seg['segFuture'], 1);
      expect(hb['hbFuture'], 'y');
      expect(lm['lmFuture'], isNull);
      // 再读回：typed 值不受未知键影响。
      final reread = MarkersDocument.fromJson(
        Map<String, dynamic>.from(written),
      );
      expect(reread.segmentLines, const [
        SegmentLine(position: Duration(milliseconds: 100)),
      ]);
      expect(reread.halfBeatLines, const [
        HalfBeatLine(position: Duration(milliseconds: 200)),
      ]);
      expect(reread.localMirrorFragments, const [
        LocalMirrorFragment(startMs: 300, endMs: 400),
      ]);
    });

    test('字节级形状：三类元素键集与次序一致（annotations 段内）', () {
      final json = const MarkersDocument(
        segmentLines: [SegmentLine(position: Duration(milliseconds: 100))],
        halfBeatLines: [HalfBeatLine(position: Duration(milliseconds: 200))],
        localMirrorFragments: [LocalMirrorFragment(startMs: 300, endMs: 400)],
      ).toJson();
      final ann = json['annotations'] as Map;
      expect(ann['segmentLines'], [
        {'timeMs': 100, 'flag': false},
      ]);
      expect(ann['halfBeatLines'], [
        {'timeMs': 200},
      ]);
      expect(ann['localMirrorFragments'], [
        {'startMs': 300, 'endMs': 400},
      ]);
    });
  });
}
