import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistence/index_file_provider.dart' show importIndexFileProvider;

/// 出站方案标识：发送方为本机每支舞
/// 持有的稳定串——同标识再导入即替换、异标识即新增。只要求「同一位发送
/// 方的同一套方案前后一致」，故按舞一次生成、随写随存；不同发送方天然
/// 不同（随机数）。
abstract interface class OutboundSchemeIdStore {
  /// 取该舞的方案标识；首次取时生成并持久化，此后恒返回同一值。
  Future<String> idFor(String videoId);
}

/// [OutboundSchemeIdStore] 真实文件实现：`scheme_ids.json`（与 index.json
/// 同级，视频标识 → 标识串的映射）。读失败/损坏按空态重建；写经实例内
/// 串行链，避免并发首次生成互相覆盖。
class OutboundSchemeIdFileStore implements OutboundSchemeIdStore {
  OutboundSchemeIdFileStore(FutureOr<File> file) : _file = file;

  final FutureOr<File> _file;
  Future<void>? _chain;

  @override
  Future<String> idFor(String videoId) {
    final run = (_chain ?? Future<void>.value()).then((_) async {
      final file = await _file;
      Map<String, Object?> map = const {};
      if (await file.exists()) {
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map) map = decoded.cast<String, Object?>();
        } on FormatException {
          map = const {};
        }
      }
      final existing = map[videoId];
      if (existing is String && existing.isNotEmpty) return existing;
      final id = _generateId();
      map = Map<String, Object?>.of(map)..[videoId] = id;
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(map));
      return id;
    });
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }
}

final Random _random = Random();

String _generateId() =>
    's-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
    '${_random.nextInt(1 << 32).toRadixString(36)}';

/// 出站方案标识注入点：生产文件在应用文档目录；测试覆盖为临时文件。
final outboundSchemeIdStoreProvider = Provider<OutboundSchemeIdStore>((ref) {
  return OutboundSchemeIdFileStore(ref.watch(importIndexFileProvider));
});
