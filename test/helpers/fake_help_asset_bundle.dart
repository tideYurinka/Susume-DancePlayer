import 'dart:convert';

import 'package:flutter/services.dart';

/// 内存假资产包：跑真枚举 / 真解析 / 真渲染的测试缝。
///
/// 真枚举走 `AssetManifest.listAssets()`，故本包按登记的全部 key 现造一份
/// `AssetManifest.bin`；文本资产按 UTF-8 编码，[binary] 里的资产原样给出
/// （图片这类非文本资产用）。
class FakeHelpAssetBundle extends CachingAssetBundle {
  FakeHelpAssetBundle(this.assets, {this.binary = const {}});

  /// 资产 key → 文本内容。
  final Map<String, String> assets;

  /// 资产 key → 原始字节（图片等）。
  final Map<String, Uint8List> binary;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return _manifestBytes();
    }
    final bytes = binary[key];
    if (bytes != null) return ByteData.sublistView(bytes);
    final text = assets[key];
    if (text == null) {
      throw StateError('假资产包里没有 $key');
    }
    return ByteData.view(Uint8List.fromList(utf8.encode(text)).buffer);
  }

  /// 与真构建产物同格式的资产清单：每个 key 一项，自身即主资产。
  ByteData _manifestBytes() {
    final data = <String, Object?>{
      for (final key in [...assets.keys, ...binary.keys])
        key: <Object?>[
          <String, Object?>{'asset': key},
        ],
    };
    return const StandardMessageCodec().encodeMessage(data)!;
  }
}

/// 1×1 透明 PNG：假资产里的图片用，足以让 `Image` 真解码。
final Uint8List onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);
