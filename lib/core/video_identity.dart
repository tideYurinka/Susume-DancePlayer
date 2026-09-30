// 视频标识（core 域）：
// 主标识 = 视频内容摘要（xxHash64，十六进制，导入时后台计算并持久化到索引）；
// 打开视频时先用「大小 + 文件名」快速键先行匹配索引立即恢复关联，
// 再以内容摘要校验，不一致按新视频处理（按新视频语义，旧条目保留）。

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// 「大小 + 文件名」快速键：`<大小字节>:<文件名>`。
///
/// 打开视频时无需读内容即可计算的匹配键；同名同大小
/// 不同内容的视频会得到相同快速键，由内容摘要校验区分。
String fastKeyFor({required String name, required int sizeBytes}) =>
    '$sizeBytes:$name';

/// 视频内容摘要计算（xxHash64）。抽象以便测试注入门控/桩实现，
/// 证明导入/打开流程不等待摘要（后台计算）。
abstract interface class ContentHasher {
  /// 计算 [file] 的内容摘要，返回 16 位小写十六进制字符串。
  Future<String> hashFile(File file);
}

/// 真实实现：在后台 isolate 中按块读取文件流式计算 xxHash64
/// （32 字节尾缓冲 + 四个累加器，不整读大文件进内存；不占用主 isolate——
/// 大文件摘要不卡顿播放/UI）。
class XxHash64ContentHasher implements ContentHasher {
  const XxHash64ContentHasher();

  @override
  Future<String> hashFile(File file) {
    final path = file.path;
    return Isolate.run(() async {
      final state = XxHash64();
      await for (final chunk in File(path).openRead()) {
        state.update(chunk);
      }
      return state.digest();
    });
  }
}

// xxHash64 常量（xxHash 官方实现，seed = 0）。
const int _prime1 = 0x9E3779B185EBCA87;
const int _prime2 = 0xC2B2AE3D27D4EB4F;
const int _prime3 = 0x165667B19E3779F9;
const int _prime4 = 0x85EBCA77C2B2AE63;
const int _prime5 = 0x27D4EB2F165667C5;

int _rotl(int value, int bits) => (value << bits) | (value >>> (64 - bits));

int _round(int acc, int lane) => _rotl(acc + lane * _prime2, 31) * _prime1;

int _mergeRound(int acc, int lane) =>
    (acc ^ _round(0, lane)) * _prime1 + _prime4;

int _read64(List<int> bytes, int offset) =>
    bytes[offset] |
    bytes[offset + 1] << 8 |
    bytes[offset + 2] << 16 |
    bytes[offset + 3] << 24 |
    bytes[offset + 4] << 32 |
    bytes[offset + 5] << 40 |
    bytes[offset + 6] << 48 |
    bytes[offset + 7] << 56;

int _read32(List<int> bytes, int offset) =>
    bytes[offset] |
    bytes[offset + 1] << 8 |
    bytes[offset + 2] << 16 |
    bytes[offset + 3] << 24;

/// 16 位小写十六进制：高位/低位分段格式化，避开负 int 的符号前缀。
String _hex64(int value) {
  final high = (value >>> 32) & 0xFFFFFFFF;
  final low = value & 0xFFFFFFFF;
  return high.toRadixString(16).padLeft(8, '0') +
      low.toRadixString(16).padLeft(8, '0');
}

/// xxHash64 流式状态（seed = 0）：32 字节尾缓冲 + 四个累加器，不整读进内存。
///
/// 依次 [update] 任意切分的字节块后 [digest]，结果与把全部字节一次喂入
/// 逐位一致；[digest] 返回 16 位小写十六进制。
class XxHash64 {
  XxHash64() : _v1 = _prime1 + _prime2, _v2 = _prime2, _v3 = 0, _v4 = -_prime1;

  int _v1;
  int _v2;
  int _v3;
  int _v4;

  int _total = 0;
  final Uint8List _tail = Uint8List(32);
  int _tailLength = 0;

  void _processStripe(List<int> data, int offset) {
    _v1 = _round(_v1, _read64(data, offset));
    _v2 = _round(_v2, _read64(data, offset + 8));
    _v3 = _round(_v3, _read64(data, offset + 16));
    _v4 = _round(_v4, _read64(data, offset + 24));
  }

  void update(List<int> data) {
    final length = data.length;
    _total += length;
    var offset = 0;

    if (_tailLength + length < 32) {
      for (var i = 0; i < length; i++) {
        _tail[_tailLength + i] = data[i];
      }
      _tailLength += length;
      return;
    }

    if (_tailLength > 0) {
      final fill = 32 - _tailLength;
      for (var i = 0; i < fill; i++) {
        _tail[_tailLength + i] = data[i];
      }
      _processStripe(_tail, 0);
      _tailLength = 0;
      offset = fill;
    }

    while (offset + 32 <= length) {
      _processStripe(data, offset);
      offset += 32;
    }

    _tailLength = length - offset;
    for (var i = 0; i < _tailLength; i++) {
      _tail[i] = data[offset + i];
    }
  }

  String digest() {
    var hash = _total >= 32
        ? _rotl(_v1, 1) + _rotl(_v2, 7) + _rotl(_v3, 12) + _rotl(_v4, 18)
        : _prime5;
    if (_total >= 32) {
      hash = _mergeRound(hash, _v1);
      hash = _mergeRound(hash, _v2);
      hash = _mergeRound(hash, _v3);
      hash = _mergeRound(hash, _v4);
    }
    hash += _total;

    var offset = 0;
    while (offset + 8 <= _tailLength) {
      hash ^= _round(0, _read64(_tail, offset));
      hash = _rotl(hash, 27) * _prime1 + _prime4;
      offset += 8;
    }
    if (offset + 4 <= _tailLength) {
      hash ^= _read32(_tail, offset) * _prime1;
      hash = _rotl(hash, 23) * _prime2 + _prime3;
      offset += 4;
    }
    while (offset < _tailLength) {
      hash ^= (_tail[offset] & 0xFF) * _prime5;
      hash = _rotl(hash, 11) * _prime1;
      offset++;
    }

    hash ^= hash >>> 33;
    hash *= _prime2;
    hash ^= hash >>> 29;
    hash *= _prime3;
    hash ^= hash >>> 32;
    return _hex64(hash);
  }
}
