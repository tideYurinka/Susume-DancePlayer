import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:dance_learning_app/core/stored_zip.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:flutter_test/flutter_test.dart';

/// susume 包模块：清单编解码与包格式
/// 版本门纯测；装配与解析经临时目录做真实 zip 往返。断言集中在包的
/// 外部行为——包进包出逐字段相等、三类错误各有明确报错、条目 STORED。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('susume_package_test');
  });

  tearDown(() async => tempDir.delete(recursive: true));

  final markers = <String, Object?>{
    'version': 8,
    'meta': <String, Object?>{'signature': <String, Object?>{'song': '野狼disco'}},
    'annotations': <String, Object?>{'segmentLines': <Object?>[]},
  };

  SusumeMediaEntry mediaSource(
    String name, {
    SusumeMediaKind kind = SusumeMediaKind.practiceClip,
    List<int> bytes = const [1, 2, 3],
  }) {
    final f = File('${tempDir.path}/src_$name');
    f.writeAsBytesSync(bytes);
    return SusumeMediaEntry(
      kind: kind,
      fileName: name,
      sizeBytes: bytes.length,
      file: f,
    );
  }

  SusumeManifest manifest({
    List<SusumeMediaEntry> media = const [],
    Map<int, int>? mastery,
    String? memberName,
    String dancer = '',
    String remark = '',
  }) => SusumeManifest(
    videoId: 'vid123',
    schemeName: '野狼disco',
    schemeDancer: dancer,
    schemeRemark: remark,
    schemeId: 'scheme-abc',
    memberName: memberName,
    mastery: mastery,
    media: media,
  );

  group('文件名', () {
    test('署名时 <歌名>.susume；未署名回落视频文件名', () {
      expect(
        susumePackageFileName(songName: '野狼disco', videoFileName: 'dance.mp4'),
        '野狼disco.susume',
      );
      expect(
        susumePackageFileName(songName: null, videoFileName: 'dance.mp4'),
        'dance.susume',
      );
      expect(
        susumePackageFileName(songName: '  ', videoFileName: 'dance.mp4'),
        'dance.susume',
      );
    });

    test('歌名中的路径与非法文件名字符被替换', () {
      expect(
        susumePackageFileName(songName: 'a/b\\c:d', videoFileName: 'v.mp4'),
        'a_b_c_d.susume',
      );
    });
  });

  group('zip 往返（临时目录）', () {
    test('署名三字段（歌名/舞者/注记）往返逐字段相等', () async {
      final out = File('${tempDir.path}/p.susume');
      await writeSusumePackage(
        output: out,
        manifest: manifest(dancer: '小如', remark: '9人版'),
        markers: markers,
      );

      final pkg = await readSusumePackage(out.path);
      expect(pkg.manifest.schemeName, '野狼disco');
      expect(pkg.manifest.schemeDancer, '小如');
      expect(pkg.manifest.schemeRemark, '9人版');
    });

    test('旧版包无舞者/注记键：按空串兜底', () async {
      // 手写不含新键的清单 zip，模拟旧版发送方。
      final file = File('${tempDir.path}/old.susume');
      await writeStoredZip(file, [
        (
          name: 'manifest.json',
          bytes: utf8.encode(jsonEncode({
            'version': kSusumePackageFormatVersion,
            'videoId': 'vid123',
            'schemeName': '野狼disco',
            'schemeId': 'scheme-abc',
          })),
          file: null,
        ),
        (name: 'markers.json', bytes: utf8.encode(jsonEncode(markers)), file: null),
      ]);

      final pkg = await readSusumePackage(file.path);
      expect(pkg.manifest.schemeDancer, isEmpty);
      expect(pkg.manifest.schemeRemark, isEmpty);
    });

    test('不带媒体：往返逐字段相等', () async {
      final out = File('${tempDir.path}/包.susume');
      await writeSusumePackage(
        output: out,
        manifest: manifest(),
        markers: markers,
      );

      final pkg = await readSusumePackage(out.path);
      expect(pkg.manifest.videoId, 'vid123');
      expect(pkg.manifest.schemeName, '野狼disco');
      expect(pkg.manifest.schemeId, 'scheme-abc');
      expect(pkg.manifest.memberName, isNull);
      expect(pkg.manifest.mastery, isNull);
      expect(pkg.manifest.media, isEmpty);
      expect(pkg.markers, markers);
    });

    test('带熟练度与组员名：往返逐字段相等', () async {
      final out = File('${tempDir.path}/p.susume');
      await writeSusumePackage(
        output: out,
        manifest: manifest(
          memberName: '果',
          mastery: const {1: 2, 3: 4},
        ),
        markers: markers,
      );

      final pkg = await readSusumePackage(out.path);
      expect(pkg.manifest.memberName, '果');
      expect(pkg.manifest.mastery, const {1: 2, 3: 4});
    });

    test('带媒体：解析出的媒体清单与字节一致', () async {
      final out = File('${tempDir.path}/p.susume');
      final video = mediaSource('source.mp4', kind: SusumeMediaKind.sourceVideo,
          bytes: List.generate(100000, (i) => i % 256));
      final clip = mediaSource('clip_1.mp4', bytes: [9, 8, 7]);
      await writeSusumePackage(
        output: out,
        manifest: manifest(media: [video, clip]),
        markers: markers,
      );

      final pkg = await readSusumePackage(out.path);
      expect(pkg.manifest.media, hasLength(2));
      expect(pkg.manifest.media[0].kind, SusumeMediaKind.sourceVideo);
      expect(pkg.manifest.media[0].fileName, 'source.mp4');
      expect(pkg.manifest.media[0].sizeBytes, 100000);
      expect(pkg.manifest.media[1].kind, SusumeMediaKind.practiceClip);
      expect(pkg.manifest.media[1].fileName, 'clip_1.mp4');
      expect(pkg.manifest.media[1].sizeBytes, 3);

      final dest = File('${tempDir.path}/extracted.mp4');
      await extractMediaEntry(out.path, pkg.manifest.media[0].entryName, dest);
      expect(dest.lengthSync(), 100000);
      expect(dest.readAsBytesSync(), video.file!.readAsBytesSync());
    });

    test('包体文件名以歌名命名', () async {
      final out = File(
        '${tempDir.path}/${susumePackageFileName(songName: '野狼disco', videoFileName: 'v.mp4')}',
      );
      await writeSusumePackage(output: out, manifest: manifest(), markers: markers);
      expect(out.existsSync(), isTrue);
    });
  });

  group('错误', () {
    Future<File> rawPackage(Map<String, Object?> manifestJson) async {
      final out = File('${tempDir.path}/raw.susume');
      final encoder = ZipFileEncoder();
      encoder.create(out.path);
      encoder.addArchiveFile(
        ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifestJson))),
      );
      encoder.addArchiveFile(
        ArchiveFile.bytes('markers.json', utf8.encode(jsonEncode(markers))),
      );
      encoder.closeSync();
      return out;
    }

    test('跨版本明确报错且不静默降级', () async {
      final f = await rawPackage({
        'version': kSusumePackageFormatVersion + 1,
        'videoId': 'vid',
        'schemeName': 'n',
        'schemeId': 's',
      });
      await expectLater(
        readSusumePackage(f.path),
        throwsA(
          isA<SusumePackageException>().having(
            (e) => e.kind,
            'kind',
            SusumePackageError.versionMismatch,
          ),
        ),
      );
    });

    test('缺字段明确报错', () async {
      final f = await rawPackage({'version': kSusumePackageFormatVersion});
      await expectLater(
        readSusumePackage(f.path),
        throwsA(
          isA<SusumePackageException>().having(
            (e) => e.kind,
            'kind',
            SusumePackageError.corrupt,
          ),
        ),
      );
    });

    test('陌生键保底：可正常解析', () async {
      final f = await rawPackage({
        'version': kSusumePackageFormatVersion,
        'videoId': 'vid123',
        'schemeName': '野狼disco',
        'schemeId': 'scheme-abc',
        'futureKey': {'x': 1},
      });
      final pkg = await readSusumePackage(f.path);
      expect(pkg.manifest.videoId, 'vid123');
    });

    test('损坏的 zip 明确报错', () async {
      final f = File('${tempDir.path}/broken.susume');
      final bytes = await rawPackage({
        'version': kSusumePackageFormatVersion,
        'videoId': 'v',
        'schemeName': 'n',
        'schemeId': 's',
      });
      final raw = bytes.readAsBytesSync();
      // 截断中央目录（zip 尾）
      f.writeAsBytesSync(raw.sublist(0, raw.length - 20));
      await expectLater(
        readSusumePackage(f.path),
        throwsA(
          isA<SusumePackageException>().having(
            (e) => e.kind,
            'kind',
            SusumePackageError.corrupt,
          ),
        ),
      );
    });

    test('mastery 键值不合法按损坏报错，不静默缺段', () async {
      final badKey = await rawPackage({
        'version': kSusumePackageFormatVersion,
        'videoId': 'v',
        'schemeName': 'n',
        'schemeId': 's',
        'mastery': {'x': 2},
      });
      await expectLater(
        readSusumePackage(badKey.path),
        throwsA(
          isA<SusumePackageException>().having(
            (e) => e.kind,
            'kind',
            SusumePackageError.corrupt,
          ),
        ),
      );
      final badValue = await rawPackage({
        'version': kSusumePackageFormatVersion,
        'videoId': 'v',
        'schemeName': 'n',
        'schemeId': 's',
        'mastery': {'1': 9},
      });
      await expectLater(
        readSusumePackage(badValue.path),
        throwsA(
          isA<SusumePackageException>().having(
            (e) => e.kind,
            'kind',
            SusumePackageError.corrupt,
          ),
        ),
      );
    });

    test('根本不是 zip 明确报错', () async {
      final f = File('${tempDir.path}/notzip.susume');
      f.writeAsStringSync('hello, world');
      await expectLater(
        readSusumePackage(f.path),
        throwsA(
          isA<SusumePackageException>().having(
            (e) => e.kind,
            'kind',
            SusumePackageError.notZip,
          ),
        ),
      );
    });

    test('写入口校验必填值', () async {
      await expectLater(
        writeSusumePackage(
          output: File('${tempDir.path}/x.susume'),
          manifest: SusumeManifest(videoId: '', schemeName: 'n', schemeId: 's'),
          markers: markers,
        ),
        throwsArgumentError,
      );
    });
  });

  group('整机包', () {
    final backupPayload = <String, Object?>{
      'index': <String, Object?>{'entries': <Object?>[]},
      'dances': <Object?>[
        <String, Object?>{
          'videoId': 'vid123',
          'markers': markers,
          'local': <String, Object?>{'version': 3},
          'schemes': <String, Object?>{'version': 1},
        },
      ],
      'device': <String, Object?>{'mirrorDefault': true},
    };

    Future<SusumePackage> writeAndRead(
      SusumeManifest manifest, {
      Map<String, Object?>? backup,
    }) async {
      final output = File('${tempDir.path}/backup.susume');
      await writeSusumePackage(
        output: output,
        manifest: manifest,
        markers: const {},
        backup: backup,
      );
      return readSusumePackage(output.path);
    }

    test('整机清单往返：kind=backup、payload 逐字段相等、无舞级必填字段', () async {
      final parsed = await writeAndRead(
        const SusumeManifest(
          kind: SusumePackageKind.backup,
          videoId: '',
          schemeName: '',
          schemeId: '',
        ),
        backup: backupPayload,
      );
      expect(parsed.manifest.kind, SusumePackageKind.backup);
      expect(parsed.backup, backupPayload);
      expect(parsed.markers, isEmpty);
    });

    test('舞级包往返：kind 缺省为 dance，backup 为 null', () async {
      final output = File('${tempDir.path}/dance.susume');
      await writeSusumePackage(
        output: output,
        manifest: manifest(),
        markers: markers,
      );
      final parsed = await readSusumePackage(output.path);
      expect(parsed.manifest.kind, SusumePackageKind.dance);
      expect(parsed.backup, isNull);
      expect(parsed.markers, markers);
    });

    test('整机包 kind=backup 但缺 payload 条目按损坏报错', () async {
      final output = File('${tempDir.path}/bad.susume');
      await writeSusumePackage(
        output: output,
        manifest: const SusumeManifest(
          kind: SusumePackageKind.backup,
          videoId: '',
          schemeName: '',
          schemeId: '',
        ),
        markers: const {},
        backup: backupPayload,
      );
      // 手工重写一个缺 backup.json 的整机包：只写清单一个条目。
      final manifestJson = jsonEncode({
        'version': kSusumePackageFormatVersion,
        'kind': 'backup',
      });
      final rebuilt = File('${tempDir.path}/rebuilt.susume');
      await writeStoredZip(rebuilt, [
        (
          name: kSusumeManifestEntry,
          bytes: utf8.encode(manifestJson),
          file: null,
        ),
      ]);

      await expectLater(
        readSusumePackage(rebuilt.path),
        throwsA(
          isA<SusumePackageException>().having(
            (e) => e.kind,
            'kind',
            SusumePackageError.corrupt,
          ),
        ),
      );
    });

    test('清单 kind 键不认识按损坏报错', () async {
      final file = File('${tempDir.path}/weird.susume');
      await writeStoredZip(file, [
        (
          name: kSusumeManifestEntry,
          bytes: utf8.encode(jsonEncode({'version': 1, 'kind': 'vault'})),
          file: null,
        ),
      ]);
      await expectLater(
        readSusumePackage(file.path),
        throwsA(
          isA<SusumePackageException>().having(
            (e) => e.kind,
            'kind',
            SusumePackageError.corrupt,
          ),
        ),
      );
    });

    test('整机装配不收 payload 即 ArgumentError；舞级装配收 payload 即 ArgumentError',
        () async {
      await expectLater(
        writeSusumePackage(
          output: File('${tempDir.path}/a.susume'),
          manifest: const SusumeManifest(
            kind: SusumePackageKind.backup,
            videoId: '',
            schemeName: '',
            schemeId: '',
          ),
          markers: const {},
        ),
        throwsArgumentError,
      );
      await expectLater(
        writeSusumePackage(
          output: File('${tempDir.path}/b.susume'),
          manifest: manifest(),
          markers: markers,
          backup: backupPayload,
        ),
        throwsArgumentError,
      );
    });

    test('整机包文件名带日期、不含舞名', () {
      final name = susumeBackupFileName(now: DateTime(2026, 9, 15, 9, 5));
      expect(name, 'Susume备份_20260915-0905.susume');
    });
  });

  group('zip 条目', () {
    test('一律 STORED（method 0）', () async {
      final out = File('${tempDir.path}/p.susume');
      final big = mediaSource('big.mp4', kind: SusumeMediaKind.sourceVideo,
          bytes: List.generate(500000, (i) => i % 7));
      await writeSusumePackage(
        output: out,
        manifest: manifest(media: [big]),
        markers: markers,
      );

      final archive = ZipDecoder().decodeBytes(out.readAsBytesSync());
      final raw = out.readAsBytesSync();
      for (final f in archive.files) {
        expect(f.compression, CompressionType.none, reason: '${f.name} 应为 STORED');
      }
      // 按原始字节核本地文件头的 method 字段：只核名字段（签名后
      // offset 26 = 名长 uint16，offset 28 起）能对上包内已知条目名的
      // 头，避免媒体字节里巧合出现 PK\x03\x04 被误当文件头
      final bd = ByteData.sublistView(raw);
      final knownNames = {'manifest.json', 'markers.json', 'media/big.mp4'};
      final sig = <int>[0x50, 0x4b, 0x03, 0x04];
      var checked = 0;
      outer:
      for (var i = 0; i <= raw.length - 30; i++) {
        for (var j = 0; j < 4; j++) {
          if (raw[i + j] != sig[j]) continue outer;
        }
        final nameLen = bd.getUint16(i + 26, Endian.little);
        if (i + 30 + nameLen > raw.length) continue;
        final name = latin1.decode(raw.sublist(i + 30, i + 30 + nameLen));
        if (!knownNames.contains(name)) continue;
        expect(
          bd.getUint16(i + 8, Endian.little),
          0,
          reason: '$name 本地文件头 method 应为 0（STORED）',
        );
        checked++;
      }
      expect(checked, 3, reason: '三个已知条目的本地文件头都应核到');
      expect(archive.files.map((f) => f.name), containsAll(
        <String>['manifest.json', 'markers.json', 'media/big.mp4'],
      ));
    });
  });
}
