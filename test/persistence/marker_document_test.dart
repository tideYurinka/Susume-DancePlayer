import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkersDocument schema 往返', () {
    test('全字段往返：镜像/署名/首尾/分段线（含 flag）/重点/beat 溯源与拍点', () {
      final doc = MarkersDocument(
        mirrored: true,
        signature: const SongSignature(
          dancer: '如',
          song: 'My Love',
          remark: '9人版',
        ),
        rangeStartMs: 0,
        rangeEndMs: 258182,
        segmentLines: const [
          SegmentLine(position: Duration(milliseconds: 4200)),
          SegmentLine(
            position: Duration(milliseconds: 38000),
            flagged: true,
          ),
        ],
        emphasizedSegments: const [0, 2],
        beat: BeatGrid(
          model: 'madmom_downbeat_rnn_full.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 5, 10, 0, 0),
          shift: 0.25,
          anchors: const [4, 12],
          beats: const [
            BeatPoint(t: 0.44, down: false),
            BeatPoint(t: 0.94, down: true),
          ],
        ),
      );

      final restored = MarkersDocument.fromJson(doc.toJson());
      expect(restored.mirrored, true);
      expect(
        restored.signature,
        const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
      );
      expect(restored.rangeStartMs, 0);
      expect(restored.rangeEndMs, 258182);
      expect(restored.segmentLines, [
        const SegmentLine(position: Duration(milliseconds: 4200)),
        const SegmentLine(
          position: Duration(milliseconds: 38000),
          flagged: true,
        ),
      ]);
      expect(restored.emphasizedSegments, [0, 2]);
      expect(restored.beat?.model, 'madmom_downbeat_rnn_full.onnx');
      expect(restored.beat?.fps, 100);
      expect(restored.beat?.generatedAt, DateTime.utc(2026, 9, 5, 10, 0, 0));
      expect(restored.beat?.shift, 0.25);
      expect(restored.beat?.anchors, [4, 12]);
      expect(restored.beat?.beats, [
        const BeatPoint(t: 0.44, down: false),
        const BeatPoint(t: 0.94, down: true),
      ]);
    });

    test('四段形状：meta/beat/corrections/annotations + version（样例）', () {
      final doc = MarkersDocument(
        signature: const SongSignature(song: 'My Love'),
        segmentLines: const [
          SegmentLine(position: Duration(milliseconds: 4200), flagged: true),
        ],
        emphasizedSegments: const [1],
        beat: BeatGrid(
          model: 'm.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 10),
          shift: 0.25,
          anchors: const [4],
          beats: const [BeatPoint(t: 0.5, down: true)],
        ),
      );
      final json = doc.toJson();
      expect(json['version'], MarkersDocument.versionPolicy.currentVersion);
      expect(json['meta'], {
        'mirrored': false,
        'localMirrorEnabled': true,
        'signature': {'dancer': '', 'song': 'My Love', 'remark': ''},
      });
      expect(json['beat'], {
        'model': 'm.onnx',
        'fps': 100,
        'generatedAt': '2026-09-10T00:00:00.000Z',
        'beats': [
          {'t': 0.5, 'down': true},
        ],
      });
      expect(json['corrections'], {
        'shift': 0.25,
        'anchors': [4],
      });
      expect(json['annotations'], {
        'range': {'startMs': 0, 'endMs': 0},
        'segmentLines': [
          {'timeMs': 4200, 'flag': true},
        ],
        'halfBeatLines': [],
        'emphasizedSegments': [1],
        'localMirrorFragments': [],
      });
      // 顶层只有版本号与四段。
      expect(json.keys.toSet(), {
        'version',
        'meta',
        'beat',
        'corrections',
        'annotations',
      });
    });

    test('未分析：beat 段缺席（不写段键），corrections 恒在', () {
      const doc = MarkersDocument();
      final json = doc.toJson();
      expect(json.containsKey('beat'), isFalse);
      expect(json['corrections'], {'shift': 0.0});
      expect(MarkersDocument.fromJson(json).beat, isNull);
    });

    test('署名 JSON 为结构三元组 dancer/song/remark，缺省字段空串', () {
      const doc = MarkersDocument(
        signature: SongSignature(song: 'My Love'),
      );
      expect(doc.toJson()['meta'], {
        'mirrored': false,
        'localMirrorEnabled': true,
        'signature': {'dancer': '', 'song': 'My Love', 'remark': ''},
      });
    });

    test('无署名时 meta 不写 signature 键，读回为 null', () {
      final meta = const MarkersDocument().toJson()['meta']
          as Map<String, dynamic>;
      expect(meta.containsKey('signature'), isFalse);
      expect(
        MarkersDocument.fromJson(const {
          'version': 8,
          'meta': {},
        }).signature,
        isNull,
      );
    });
  });

  group('封面位置字段（meta 段）', () {
    test('缺省与不存在：读回 null（语义 = 跟随首线，由读面兜底）', () {
      expect(const MarkersDocument().coverPositionMs, isNull);
      expect(
        MarkersDocument.fromJson(const {
          'version': 8,
          'meta': {'mirrored': false},
        }).coverPositionMs,
        isNull,
      );
    });

    test('缺省写盘不写该键；显式位置才写键', () {
      final absent = const MarkersDocument().toJson()['meta']
          as Map<String, dynamic>;
      expect(absent.containsKey('coverPositionMs'), isFalse);

      const doc = MarkersDocument(coverPositionMs: 12345);
      expect(doc.toJson()['meta']['coverPositionMs'], 12345);
    });

    test('写入读取往返：位置值原样回来', () {
      const doc = MarkersDocument(coverPositionMs: 4200);
      final restored = MarkersDocument.fromJson(doc.toJson());
      expect(restored.coverPositionMs, 4200);
    });

    test('清除（恢复跟随首线）：写回 null 后键消失', () {
      const doc = MarkersDocument(coverPositionMs: 4200);
      final cleared = doc.withCoverPosition(null);
      expect(cleared.coverPositionMs, isNull);
      expect(
        (cleared.toJson()['meta'] as Map<String, dynamic>).containsKey(
          'coverPositionMs',
        ),
        isFalse,
      );
    });

    test('类型不符兜底 null（不把坏值当位置）', () {
      for (final bad in ['1200', 1.5, true]) {
        final doc = MarkersDocument.fromJson({
          'version': 8,
          'meta': {'coverPositionMs': bad},
        });
        expect(doc.coverPositionMs, isNull, reason: '值 $bad 应兜底 null');
      }
    });

    test('写入封面位置不丢同文档其它字段（署名/首尾/分段线/meta 未知键）', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'meta': {
          'mirrored': true,
          'signature': {'dancer': '如', 'song': '真值名', 'remark': ''},
          'metaFuture': 'keep-me',
        },
        'annotations': {
          'range': {'startMs': 10000, 'endMs': 120000},
          'segmentLines': [
            {'timeMs': 60000, 'flag': false},
          ],
          'halfBeatLines': [],
          'emphasizedSegments': [],
          'localMirrorFragments': [],
        },
      });

      final written = doc.withCoverPosition(30000).toJson();
      expect(written['meta']['coverPositionMs'], 30000);
      expect(written['meta']['metaFuture'], 'keep-me');
      expect(written['meta']['mirrored'], true);
      expect(written['meta']['signature'], {
        'dancer': '如',
        'song': '真值名',
        'remark': '',
      });
      expect(written['annotations']['range'], {
        'startMs': 10000,
        'endMs': 120000,
      });
      expect(written['annotations']['segmentLines'], [
        {'timeMs': 60000, 'flag': false},
      ]);
    });

    test('封面位置按「我的标注方案」原文出包：分享往返后一致', () {
      final original = const MarkersDocument(
        signature: SongSignature(song: '歌'),
        coverPositionMs: 8800,
      ).toJson();
      // 分享包携带 markers 原文（JSON 往返即包内进出）。
      final roundTripped = MarkersDocument.fromJson(
        Map<String, dynamic>.from(original),
      );
      expect(roundTripped.coverPositionMs, 8800);
      expect(
        roundTripped,
        const MarkersDocument(
          signature: SongSignature(song: '歌'),
          coverPositionMs: 8800,
        ),
      );
    });
  });

  group('localMirrorEnabled 字段（meta 段）', () {
    test('构造取值往返：false 写键、读回 false', () {
      const doc = MarkersDocument(localMirrorEnabled: false);
      final json = doc.toJson();
      expect(json['version'], MarkersDocument.versionPolicy.currentVersion);
      expect(json['meta']['localMirrorEnabled'], false);
      final restored = MarkersDocument.fromJson(json);
      expect(restored.localMirrorEnabled, isFalse);
    });

    test('缺省构造兜底 true；写出带键', () {
      const doc = MarkersDocument();
      expect(doc.localMirrorEnabled, isTrue);
      expect(doc.toJson()['meta']['localMirrorEnabled'], true);
    });

    test('缺键兜底 true（新文件与首建初值的口径）', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'meta': {'mirrored': true},
      });
      expect(doc.localMirrorEnabled, isTrue);
      expect(doc.mirrored, isTrue);
    });

    test('类型不符兜底 true（读法与同段 mirrored 同款）', () {
      for (final bad in ['yes', 1, null]) {
        final doc = MarkersDocument.fromJson({
          'version': 8,
          'meta': {'localMirrorEnabled': bad},
        });
        expect(doc.localMirrorEnabled, isTrue, reason: '值 $bad 应兜底 true');
      }
    });

    test('读入无键文件再写出：只多 localMirrorEnabled 键，其余原样', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'meta': {'mirrored': true, 'p1Reserved': 'x'},
      });
      final json = doc.toJson();
      expect(json['version'], MarkersDocument.versionPolicy.currentVersion);
      expect(json['meta'], {
        'mirrored': true,
        'localMirrorEnabled': true,
        'p1Reserved': 'x',
      });
    });

    test('该字段参与文档相等判定与 hashCode', () {
      const off = MarkersDocument(localMirrorEnabled: false);
      expect(off, isNot(const MarkersDocument()));
      expect(off, const MarkersDocument(localMirrorEnabled: false));
      expect(
        off.hashCode,
        const MarkersDocument(localMirrorEnabled: false).hashCode,
      );
      final roundtripped = MarkersDocument.fromJson(off.toJson());
      expect(roundtripped, off);
      expect(roundtripped.hashCode, off.hashCode);
    });
  });

  group('MarkersDocument 版本政策', () {
    test('版本头读不出 → 认识多少读多少 + 只读', () {
      const onDisk = <String, dynamic>{
        'meta': {'mirrored': true},
        'annotations': {
          'range': {'startMs': 0, 'endMs': 10},
        },
        'docFuture': 1,
      };
      final doc = MarkersDocument.fromJson(Map<String, dynamic>.of(onDisk));
      expect(doc.mirrored, isTrue);
      expect(doc.rangeEndMs, 10);
      expect(doc.extra, {'docFuture': 1});
      expect(MarkersDocument.versionPolicy.isWritable(onDisk), isFalse);
    });

    test('低于地板（v1–v6）→ 空态（唯一合法的读空）', () {
      for (var version = 1; version <= 6; version++) {
        final doc = MarkersDocument.fromJson({
          'version': version,
          'meta': {'mirrored': true},
          'annotations': {
            'range': {'startMs': 0, 'endMs': 10},
          },
        });
        expect(doc, const MarkersDocument.empty(), reason: 'version=$version');
        expect(doc.mirrored, isFalse, reason: 'version=$version');
      }
    });

    test('更高版本（v10）→ 认识多少读多少 + 只读', () {
      const onDisk = <String, dynamic>{
        'version': 10,
        'meta': {'mirrored': true},
      };
      final doc = MarkersDocument.fromJson(Map<String, dynamic>.of(onDisk));
      expect(doc.mirrored, isTrue);
      expect(MarkersDocument.versionPolicy.isWritable(onDisk), isFalse);
    });

    test('文件缺失（空 JSON）得到空态文档（等价默认值）', () {
      expect(
        MarkersDocument.fromJson(const {}),
        const MarkersDocument.empty(),
      );
    });
  });

  group('MarkersDocument 逐层陌生键保底', () {
    test('文档层、段层、元素层的未知键都原样带回、写回原样', () {
      final fromFile = MarkersDocument.fromJson(const {
        'version': 8,
        'meta': {
          'mirrored': true,
          'metaFuture': 'keep-me',
        },
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'generatedAt': '2026-09-10T00:00:00.000Z',
          'beats': [],
          'beatFuture': 7,
        },
        'corrections': {
          'shift': 0.25,
          'anchors': [4],
          'corrFuture': {'x': 1},
        },
        'annotations': {
          'range': {
            'startMs': 0,
            'endMs': 100,
            'rangeFuture': 'keep',
          },
          'segmentLines': [
            {'timeMs': 100, 'flag': false, 'segFuture': 1},
          ],
          'annFuture': [1, 2],
        },
        'docFuture': true,
      });

      expect(fromFile.extra, {'docFuture': true});
      expect(fromFile.metaExtra, {'metaFuture': 'keep-me'});
      expect(fromFile.beat?.extra, {'beatFuture': 7});
      expect(fromFile.rangeExtra, {'rangeFuture': 'keep'});
      expect(fromFile.correctionsExtra, {'corrFuture': {'x': 1}});
      expect(fromFile.annotationsExtra, {'annFuture': [1, 2]});
      expect(
        fromFile.segmentLines.single.extra,
        {'segFuture': 1},
      );

      final written = fromFile.toJson();
      expect(written['docFuture'], true);
      expect(written['meta']['metaFuture'], 'keep-me');
      expect(written['beat']['beatFuture'], 7);
      expect(written['corrections']['corrFuture'], {'x': 1});
      expect(written['annotations']['annFuture'], [1, 2]);
      expect(written['annotations']['range']['rangeFuture'], 'keep');
      expect(
        (written['annotations']['segmentLines'] as List).single['segFuture'],
        1,
      );
    });

    test('保底区不覆盖已登记字段：段层 extra 塞同名键、注册值胜出', () {
      final doc = MarkersDocument(
        mirrored: true,
        beat: BeatGrid(
          model: 'm.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 10),
          shift: 0.25,
          anchors: const [4],
          beats: const [BeatPoint(t: 0.5, down: true)],
          extra: {'model': 'hijack'},
        ),
        metaExtra: {'mirrored': false},
        correctionsExtra: {'shift': 9.9, 'anchors': 'hijack'},
        annotationsExtra: {'segmentLines': 'hijack', 'range': 'hijack'},
      );
      final written = doc.toJson();
      expect(written['meta']['mirrored'], true);
      expect(written['beat']['model'], 'm.onnx');
      expect(written['corrections']['shift'], 0.25);
      expect(written['corrections']['anchors'], [4]);
      expect(written['annotations']['segmentLines'], isA<List>());
      expect(written['annotations']['range'], {
        'startMs': 0,
        'endMs': 0,
      });
    });

    test('本版本字段与扩展字段互不干扰', () {
      final fromFile = MarkersDocument.fromJson(const {
        'version': 8,
        'meta': {'mirrored': true},
        'p1Reserved': 'x',
      });
      final updated = fromFile.withSegmentLines(const [
        SegmentLine(position: Duration(milliseconds: 5)),
      ]);
      final json = updated.toJson();
      expect(json['meta']['mirrored'], true);
      expect(json['p1Reserved'], 'x');
      expect(json['version'], MarkersDocument.versionPolicy.currentVersion);
    });

    test('内容相同即相等（List 深比较）且 hashCode 一致', () {
      const a = MarkersDocument(
        segmentLines: [
          SegmentLine(position: Duration(milliseconds: 4200), flagged: true),
        ],
        emphasizedSegments: [0],
      );
      final b = MarkersDocument.fromJson(a.toJson());
      expect(b, a);
      expect(b.hashCode, a.hashCode);
    });

    test('归属固定：公开标记文件不携带按舞倍速记忆键', () {
      final json = const MarkersDocument(mirrored: true).toJson();
      expect(json.containsKey('speedRate'), isFalse);
      expect(
        (json['meta'] as Map<String, dynamic>).containsKey('speedRate'),
        isFalse,
      );
    });
  });

  group('MarkersDocument 可分享投影', () {
    test('公开字段全随包；私密键、未登记键与保底区一律不进包', () {
      const onDisk = <String, Object?>{
        'version': 8,
        'meta': <String, Object?>{
          'mirrored': true,
          'localMirrorEnabled': false,
          'coverPositionMs': 42000,
          // 今后若有人往公开标记文件加私密字段，未标记 shareable 即不随包。
          'practiceNote': 'private',
          'metaFuture': 'keep-me',
        },
        'corrections': <String, Object?>{'shift': 0.25, 'anchors': [4]},
        'annotations': <String, Object?>{
          'range': <String, Object?>{'startMs': 0, 'endMs': 100},
          'segmentLines': [
            <String, Object?>{'timeMs': 100, 'flag': false},
          ],
          'annFuture': [1, 2],
        },
        'docFuture': true,
      };

      expect(MarkersDocument.shareableJson(onDisk), {
        'version': 8,
        'meta': {
          'mirrored': true,
          'localMirrorEnabled': false,
          'coverPositionMs': 42000,
        },
        'corrections': {'shift': 0.25, 'anchors': [4]},
        'annotations': {
          'range': {'startMs': 0, 'endMs': 100},
          'segmentLines': [
            {'timeMs': 100, 'flag': false},
          ],
        },
      });
    });
  });

  group('源画面取景选区字段（meta 段）', () {
    test('标记文件版本为 9：加字段、段与行序不变', () {
      final json = const MarkersDocument().toJson();
      expect(json['version'], MarkersDocument.versionPolicy.currentVersion);
      expect(json['version'], 9);
      expect(json.keys, contains('meta'));
    });

    test('取景选区写入读取往返：四边原样回来；参与相等', () {
      const selection = FramingSelection(
        left: 0.1,
        top: 0.2,
        right: 0.6,
        bottom: 0.8,
      );
      final json = const MarkersDocument(framingSelection: selection).toJson();
      expect((json['meta'] as Map)['framingSelection'], {
        'left': 0.1,
        'top': 0.2,
        'right': 0.6,
        'bottom': 0.8,
      });
      final restored = MarkersDocument.fromJson(json);
      expect(restored.framingSelection, selection);
      expect(restored, const MarkersDocument(framingSelection: selection));
    });

    test('未调过省键：null 不写 framingSelection', () {
      final json = const MarkersDocument().toJson();
      expect((json['meta'] as Map).containsKey('framingSelection'), isFalse);
    });

    test('整帧选区是已存值：照常写键（与未调过在显示上不可区分）', () {
      final json = const MarkersDocument(
        framingSelection: FramingSelection.fullFrame(),
      ).toJson();
      expect((json['meta'] as Map)['framingSelection'], {
        'left': 0.0,
        'top': 0.0,
        'right': 1.0,
        'bottom': 1.0,
      });
    });

    test('非法值兜底：非对象、缺分量、类型不符、越出整帧、退化区都按未调过', () {
      for (final raw in const [
        'bad',
        42,
        <dynamic, dynamic>{},
        <dynamic, dynamic>{'left': 0.1, 'top': 0.2, 'right': 0.6},
        <dynamic, dynamic>{
          'left': 'a',
          'top': 0.2,
          'right': 0.6,
          'bottom': 0.8,
        },
        <dynamic, dynamic>{
          'left': 0.1,
          'top': 0.2,
          'right': null,
          'bottom': 0.8,
        },
        // 越出整帧：写侧只写合法值，这些只可能来自手改/损坏文件。
        <dynamic, dynamic>{
          'left': -0.1,
          'top': 0.2,
          'right': 0.6,
          'bottom': 0.8,
        },
        <dynamic, dynamic>{
          'left': 0.1,
          'top': 0.2,
          'right': 1.2,
          'bottom': 0.8,
        },
        <dynamic, dynamic>{
          'left': 0.1,
          'top': -0.1,
          'right': 0.6,
          'bottom': 1.2,
        },
        // 退化区（宽或高非正）。
        <dynamic, dynamic>{
          'left': 0.4,
          'top': 0.2,
          'right': 0.4,
          'bottom': 0.8,
        },
        <dynamic, dynamic>{
          'left': 0.1,
          'top': 0.8,
          'right': 0.6,
          'bottom': 0.8,
        },
        <dynamic, dynamic>{
          'left': 0.6,
          'top': 0.2,
          'right': 0.1,
          'bottom': 0.8,
        },
      ]) {
        final doc = MarkersDocument.fromJson({
          'version': MarkersDocument.versionPolicy.currentVersion,
          'meta': {'framingSelection': raw},
        });
        expect(doc.framingSelection, isNull, reason: 'raw=$raw');
      }
    });

    test('写入取景选区不丢 meta 段其它字段与未知键（逐层保底）', () {
      final fromFile = MarkersDocument.fromJson({
        'version': MarkersDocument.versionPolicy.currentVersion,
        'meta': {
          'mirrored': true,
          'metaReserved': {'keep': true},
        },
      });
      final json = fromFile
          .withFramingSelection(
            const FramingSelection(
              left: 0.2,
              top: 0.2,
              right: 0.8,
              bottom: 0.8,
            ),
          )
          .toJson();
      final meta = json['meta'] as Map;
      expect(meta['mirrored'], true);
      expect(meta['metaReserved'], {'keep': true});
      expect(meta['framingSelection'], {
        'left': 0.2,
        'top': 0.2,
        'right': 0.8,
        'bottom': 0.8,
      });
    });

    test('清除（复位）：写 null 后键消失', () {
      const selection = FramingSelection(
        left: 0.2,
        top: 0.2,
        right: 0.8,
        bottom: 0.8,
      );
      final cleared = const MarkersDocument(
        framingSelection: selection,
      ).withFramingSelection(null);
      expect(
        (cleared.toJson()['meta'] as Map).containsKey('framingSelection'),
        isFalse,
      );
    });
  });

  group('v7 → v8 迁移', () {
    // 事故回归夹具：v0.1.2 实际落盘的 v7 形状（键名以
    // `git show v0.1.2:lib/persistence/marker_document.dart` 为准）——
    // meta 无 framingBand、annotations 无 segmentDensities。文档级／段级／
    // 元素级各放一个陌生键，证明逐层保底区随迁移逐字往返。
    final v7Doc = <String, dynamic>{
      'version': 7,
      'docFuture': {'keep': 1},
      'meta': {
        'mirrored': true,
        'localMirrorEnabled': false,
        'signature': {'dancer': '如', 'song': 'My Love', 'remark': '9人版'},
        'coverPositionMs': 8800,
        'metaFuture': 'keep-meta',
      },
      'beat': {
        'model': 'madmom_downbeat_rnn_full.onnx',
        'fps': 100,
        'generatedAt': '2026-09-05T10:00:00.000Z',
        'beats': [
          {'t': 0.44, 'down': false},
          {'t': 0.94, 'down': true},
        ],
        'beatFuture': 7,
      },
      'corrections': {
        'shift': 0.25,
        'density': 2.0,
        'anchors': [4, 12],
        'corrFuture': {'keep': true},
      },
      'annotations': {
        'range': {'startMs': 1000, 'endMs': 258182, 'rangeFuture': 'keep'},
        'segmentLines': [
          {'timeMs': 4200, 'flag': false, 'segFuture': 1},
          {'timeMs': 38000, 'flag': true},
        ],
        'halfBeatLines': [
          {'timeMs': 100},
        ],
        'emphasizedSegments': [0, 2],
        'localMirrorFragments': [
          {'startMs': 1000, 'endMs': 3000},
        ],
        'annFuture': [1, 2],
      },
      'notes': {
        'notes': [
          {
            'startMs': 1000,
            'endMs': 3000,
            'text': '@果果 注意',
            'locked': false,
            'geometry': {'centerX': 0.5, 'centerY': 0.5, 'scale': 1.0},
            'noteFuture': 'keep',
          },
        ],
        'notesFuture': 'keep',
      },
      'roster': {
        'dancers': [
          {'name': '果果', 'color': 0xFFFFD54F},
        ],
        'rosterFuture': 'keep',
      },
    };

    test('结构断言：版本链从地板无缝连到本版', () {
      expect(MarkersDocument.versionPolicy.floor, 7);
      expect(MarkersDocument.versionPolicy.currentVersion, 9);
      expect(
        MarkersDocument.versionPolicy.steps.map((step) => step.from),
        [7, 8],
      );
    });

    test('v7 文件读入：meta/corrections/annotations 各元素逐项在场', () {
      final doc = MarkersDocument.fromJson(v7Doc);

      // meta：署名、封面位置、镜像、局部镜像。
      expect(doc.mirrored, isTrue);
      expect(doc.localMirrorEnabled, isFalse);
      expect(
        doc.signature,
        const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
      );
      expect(doc.coverPositionMs, 8800);

      // beat + corrections：网格与人工修正（含整曲倍频）。
      expect(doc.beat?.model, 'madmom_downbeat_rnn_full.onnx');
      expect(doc.beat?.fps, 100);
      expect(doc.beat?.generatedAt, DateTime.utc(2026, 9, 5, 10, 0, 0));
      expect(doc.beat?.shift, 0.25);
      expect(doc.beat?.density, 2.0);
      expect(doc.beat?.anchors, [4, 12]);
      expect(doc.beat?.beats, const [
        BeatPoint(t: 0.44, down: false),
        BeatPoint(t: 0.94, down: true),
      ]);

      // annotations：首尾、分段线、半拍线、重点、局部镜像片段。
      expect(doc.rangeStartMs, 1000);
      expect(doc.rangeEndMs, 258182);
      expect(doc.segmentLines.length, 2);
      expect(doc.segmentLines[0].position.inMilliseconds, 4200);
      expect(doc.segmentLines[0].flagged, isFalse);
      expect(doc.segmentLines[1].position.inMilliseconds, 38000);
      expect(doc.segmentLines[1].flagged, isTrue);
      expect(doc.halfBeatLines.single.position.inMilliseconds, 100);
      expect(doc.emphasizedSegments, [0, 2]);
      expect(doc.localMirrorFragments.single.startMs, 1000);
      expect(doc.localMirrorFragments.single.endMs, 3000);

      // notes / roster：备注贴纸与舞者名册。
      expect(doc.notes.single.text, '@果果 注意');
      expect(doc.notes.single.locked, isFalse);
      expect(doc.roster.single.name, '果果');
      expect(doc.roster.single.color, 0xFFFFD54F);

      // v8/v9 新增键缺省：不预写、读面为空。
      expect(doc.framingSelection, isNull);
      expect(doc.segmentDensities, isEmpty);

      // 陌生键逐层进保底区。
      expect(doc.extra, {'docFuture': {'keep': 1}});
      expect(doc.metaExtra, {'metaFuture': 'keep-meta'});
      expect(doc.beat?.extra, {'beatFuture': 7});
      expect(doc.correctionsExtra, {'corrFuture': {'keep': true}});
      expect(doc.annotationsExtra, {'annFuture': [1, 2]});
      expect(doc.rangeExtra, {'rangeFuture': 'keep'});
      expect(doc.segmentLines[0].extra, {'segFuture': 1});
      expect(doc.notesExtra, {'notesFuture': 'keep'});
      expect(doc.notes.single.extra, {'noteFuture': 'keep'});
      expect(doc.rosterExtra, {'rosterFuture': 'keep'});
    });

    test('v7 写回：version == 本版，内容等价且逐层陌生键仍在', () {
      final doc = MarkersDocument.fromJson(v7Doc);
      final written = doc.toJson();

      expect(written['version'], 9);
      expect(written['docFuture'], {'keep': 1});
      expect(written['meta']['metaFuture'], 'keep-meta');
      expect(written['beat']['beatFuture'], 7);
      expect(written['corrections']['corrFuture'], {'keep': true});
      expect(written['annotations']['annFuture'], [1, 2]);
      expect(written['annotations']['range']['rangeFuture'], 'keep');
      expect(
        (written['annotations']['segmentLines'] as List).first['segFuture'],
        1,
      );
      expect(written['notes']['notesFuture'], 'keep');
      expect((written['notes']['notes'] as List).single['noteFuture'], 'keep');
      expect(written['roster']['rosterFuture'], 'keep');

      // v8/v9 新增键不预写（缺省即「原样」/未调过）。
      expect((written['meta'] as Map).containsKey('framingSelection'), isFalse);
      expect(
        (written['annotations'] as Map).containsKey('segmentDensities'),
        isFalse,
      );

      // 读回写出的本版与迁移后的文档等价。
      final reopened = MarkersDocument.fromJson(written);
      expect(reopened, doc);
    });

    test('迁移幂等：迁后文档再读再写不再变化', () {
      final once = MarkersDocument.fromJson(v7Doc).toJson();
      final twice = MarkersDocument.fromJson(once).toJson();
      expect(twice, once);
    });

    test('v1–v6 从未分发：仍按空态整份丢弃', () {
      for (var version = 1; version <= 6; version++) {
        final doc = MarkersDocument.fromJson({
          'version': version,
          'meta': {
            'mirrored': true,
            'signature': {'dancer': '旧', 'song': '旧歌', 'remark': ''},
          },
          'annotations': {
            'range': {'startMs': 1000, 'endMs': 200000},
            'segmentLines': [
              {'timeMs': 4200, 'flag': true},
            ],
          },
          'beat': {
            'model': 'm.onnx',
            'fps': 100,
            'generatedAt': '2026-09-10T00:00:00.000Z',
            'beats': [
              {'t': 0.5, 'down': true},
            ],
          },
        });
        expect(
          doc,
          const MarkersDocument.empty(),
          reason: 'version=$version 应整份丢弃',
        );
        expect(doc.segmentLines, isEmpty, reason: 'version=$version');
        expect(doc.beat, isNull, reason: 'version=$version');
      }
    });
  });

  group('v8 → v9 迁移', () {
    // v0.1.3 的 v8 形状：旧取景字段只可能来自未随发布落盘的 v8（framingBand
    // 加在 tag 之后）；文档级／段级／元素级各放一个陌生键，证明其余内容与
    // 逐层保底区随迁移逐字往返。
    final v8Doc = <String, dynamic>{
      'version': 8,
      'docFuture': {'keep': 1},
      'meta': {
        'mirrored': true,
        'signature': {'dancer': '如', 'song': 'My Love', 'remark': ''},
        'coverPositionMs': 8800,
        'framingBand': {'top': 0.2, 'bottom': 0.7, 'centerX': 0.45},
        'metaFuture': 'keep-meta',
      },
      'annotations': {
        'range': {'startMs': 1000, 'endMs': 258182},
        'segmentLines': [
          {'timeMs': 4200, 'flag': true, 'segFuture': 1},
        ],
        'annFuture': [1, 2],
      },
    };

    test('含旧取景字段的 v8：读入即未调过，其余字段逐字不变、陌生键仍在', () {
      final doc = MarkersDocument.fromJson(v8Doc);

      expect(doc.framingSelection, isNull, reason: '旧取景字段只丢不换算');
      expect(doc.mirrored, isTrue);
      expect(doc.coverPositionMs, 8800);
      expect(doc.rangeStartMs, 1000);
      expect(doc.segmentLines.single.position.inMilliseconds, 4200);
      expect(doc.extra, {'docFuture': {'keep': 1}});
      expect(doc.metaExtra, {'metaFuture': 'keep-meta'});
      expect(doc.annotationsExtra, {'annFuture': [1, 2]});
      expect(doc.segmentLines.single.extra, {'segFuture': 1});
    });

    test('写回后版本为 9 且旧字段消失', () {
      final written = MarkersDocument.fromJson(v8Doc).toJson();

      expect(written['version'], 9);
      expect((written['meta'] as Map).containsKey('framingBand'), isFalse);
      expect(written['meta']['metaFuture'], 'keep-meta');
      expect(written['docFuture'], {'keep': 1});
      expect(written['meta']['coverPositionMs'], 8800);
      expect((written['annotations'] as Map)['annFuture'], [1, 2]);
      expect(
        (written['annotations']['segmentLines'] as List).first['segFuture'],
        1,
      );
    });

    test('迁移幂等：迁后文档再读再写不再变化', () {
      final once = MarkersDocument.fromJson(v8Doc).toJson();
      final twice = MarkersDocument.fromJson(once).toJson();
      expect(twice, once);
    });

    test('已发布的 v8 文件（本就没有取景字段）迁移前后逐字不变', () {
      final published = <String, Object?>{
        'version': 8,
        'meta': {
          'mirrored': false,
          'coverPositionMs': 8800,
          'metaFuture': 'keep',
        },
        'annotations': {
          'range': {'startMs': 0, 'endMs': 1000},
          'annFuture': {'keep': true},
        },
      };
      final upgraded = MarkersDocument.versionPolicy.upgrade(published);
      expect(upgraded.writable, isTrue);
      expect(upgraded.json, {...published, 'version': 9});
    });
  });
}
