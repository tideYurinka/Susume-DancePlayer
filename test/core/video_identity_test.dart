import 'dart:io';

import 'package:dance_learning_app/core/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 确定性字节模式（i % 251），与参考实现（xxHash 官方 C 库）逐位对齐。
List<int> pattern(int length) => List<int>.generate(length, (i) => i % 251);

void main() {
  group('fastKeyFor（大小 + 文件名快速键）', () {
    test('由大小与文件名组成，同名同大小得到相同快速键', () {
      expect(fastKeyFor(name: 'dance.mp4', sizeBytes: 1024), '1024:dance.mp4');
      expect(
        fastKeyFor(name: 'dance.mp4', sizeBytes: 1024),
        fastKeyFor(name: 'dance.mp4', sizeBytes: 1024),
      );
    });

    test('大小或文件名不同则快速键不同', () {
      expect(
        fastKeyFor(name: 'dance.mp4', sizeBytes: 1024),
        isNot(fastKeyFor(name: 'dance.mp4', sizeBytes: 2048)),
      );
      expect(
        fastKeyFor(name: 'dance.mp4', sizeBytes: 1024),
        isNot(fastKeyFor(name: 'other.mp4', sizeBytes: 1024)),
      );
    });
  });

  group('XxHash64ContentHasher（xxHash64 内容摘要）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hash_test');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<File> write(String name, List<int> bytes) async {
      final file = File(p.join(tempDir.path, name));
      await file.writeAsBytes(bytes);
      return file;
    }

    /// 确定性字节模式与参考实现逐位对齐。
    const hasher = XxHash64ContentHasher();

    // 规范向量来自 xxHash 官方实现（python-xxhash 4.0.1，seed=0），
    // 摘要字节即身份，故两侧必须逐位一致。
    test('规范向量：空串 / a / abc / message digest', () async {
      expect(
        await hasher.hashFile(await write('empty.mp4', [])),
        'ef46db3751d8e999',
      );
      expect(
        await hasher.hashFile(await write('a.mp4', [0x61])),
        'd24ec4f1a98c6e5b',
      );
      expect(
        await hasher.hashFile(await write('abc.mp4', [0x61, 0x62, 0x63])),
        '44bc2cf5ad770999',
      );
      expect(
        await hasher.hashFile(
          await write('md.mp4', 'message digest'.codeUnits),
        ),
        '066ed728fceeb3be',
      );
    });

    test('规范向量：字母表 / 字母数字串 / 长数字串', () async {
      expect(
        await hasher.hashFile(
          await write('alpha.mp4', 'abcdefghijklmnopqrstuvwxyz'.codeUnits),
        ),
        'cfe1f278fa89835c',
      );
      expect(
        await hasher.hashFile(
          await write(
            'alnum.mp4',
            ('ABCDEFGHIJKLMNOPQRSTUVWXYZ'
                    'abcdefghijklmnopqrstuvwxyz'
                    '0123456789')
                .codeUnits,
          ),
        ),
        'aaa46907d3047814',
      );
      expect(
        await hasher.hashFile(
          await write('digits.mp4', ('1234567890' * 8).codeUnits),
        ),
        'e04a477f19ee145d',
      );
    });

    test('流式多长度边界与参考实现一致（32 字节条带 / 8·4·1 字节尾）', () async {
      const expected = {
        0: 'ef46db3751d8e999',
        1: 'e934a84adb052768',
        3: 'e5c7bb4533bc65dd',
        4: 'ffced8604453cc1e',
        7: '14cc643f630c72d2',
        8: '884a173614b81b8d',
        15: 'a948f5f0f6abac2d',
        16: '44b6ef2fb84169f7',
        31: 'c346d2b59b4d8ee1',
        32: 'cbf59c5116ff32b4',
        33: '0c535d1acafb8ead',
        63: 'e26aa9e2a95f8e4f',
        64: 'f7c67301db6713f0',
        65: 'c31eb63b2ae4465b',
        255: '566d96b832b967c1',
        256: 'f33944343ee85824',
        1000: 'f306f04aa88b54d3',
      };
      for (final entry in expected.entries) {
        final file = await write('p${entry.key}.mp4', pattern(entry.key));
        expect(
          await hasher.hashFile(file),
          entry.value,
          reason: '长度 ${entry.key} 的摘要应与参考实现一致',
        );
      }
    });

    test('跨块大文件（1 MiB）流式哈希与参考实现一致', () async {
      final file = await write('big.mp4', pattern(1 << 20));
      expect(await hasher.hashFile(file), '89ac0399c4464a31');
    });

    test('内容不同则摘要不同（视频标识语义：内容指纹）', () async {
      final a = await write('a.mp4', [1, 2, 3]);
      final b = await write('b.mp4', [1, 2, 4]);
      expect(await hasher.hashFile(a), isNot(await hasher.hashFile(b)));
    });

    test('摘要为 16 位小写十六进制（xxHash64 定长）', () async {
      final hash = await hasher.hashFile(await write('fmt.mp4', [7, 8, 9]));
      expect(hash, matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('XxHash64 流式状态（分块喂入 = 整块一次喂入）', () {
    String whole(List<int> bytes) => (XxHash64()..update(bytes)).digest();

    String chunked(List<int> bytes, int chunkSize) {
      final state = XxHash64();
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, bytes.length);
        state.update(bytes.sublist(offset, end));
      }
      return state.digest();
    }

    test('任意块切分与整块喂入逐位一致（含非 32 倍数的块边界）', () {
      final bytes = pattern(5000);
      final expected = whole(bytes);
      for (final size in [
        1,
        3,
        5,
        7,
        8,
        15,
        16,
        17,
        31,
        32,
        33,
        63,
        64,
        65,
        100,
        999,
        4096,
        5000,
      ]) {
        expect(chunked(bytes, size), expected, reason: '块大小 $size 的分块结果应与整块一致');
      }
    });

    test('分块结果锚定规范向量（独立参考值，非自证）', () {
      expect(chunked([0x61, 0x62, 0x63], 2), '44bc2cf5ad770999');
      expect(whole(pattern(1 << 20)), '89ac0399c4464a31');
    });

    test('空输入与仅尾缓冲长度：分块与整块一致', () {
      expect(chunked(const [], 1), whole(const []));
      expect(chunked(const [1, 2, 3], 1), whole(const [1, 2, 3]));
    });
  });
}
