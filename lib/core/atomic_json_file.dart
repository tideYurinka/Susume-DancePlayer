import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'private_json.dart';

/// 设备级 JSON 文件深模块：一个文件路径一个实例。
///
/// [PrivateJsonStorage] 的真实文件实现。
///
/// 三个同源 JSON 文件（全局私密 `global_private.json`、镜像索引
/// `index.json`、未来练舞统计与按视频私密文件）共享的落盘机制：
/// - 读：文件缺失/损坏兜底为空 Map（FileSystemException / FormatException /
///   顶层非对象），不抛错（首启/升级不炸）；
/// - 写：先落临时文件 `${file.path}.tmp` 再原子重命名，读侧永不看到半截
///   JSON；父目录不存在时递归创建；
/// - 串行写链：全部读写经单条链执行，并发写不互相覆盖；
/// - [mutate]：原子读改写并入同一条写链（链内 read → apply → write），
///   并发 mutate 无 lost-update；
/// - [delete]：删除底层文件与 `.tmp` 残留，并入同一条写链（排在已排队的
///   写之后）。
class AtomicJsonFile implements PrivateJsonStorage {
  AtomicJsonFile(this._file);

  /// 目标文件；接受 [File] 或尚未解析的 `Future<File>`（生产由
  /// path_provider 异步解析，测试直接传临时文件）。
  final FutureOr<File> _file;

  /// 内部写链：串行化并发读写，防止互相覆盖丢失更新。
  Future<void> _writeChain = Future<void>.value();

  /// 目标文件（异步解析 path_provider 的 Future）。
  Future<File> resolveFile() async => await _file;

  /// 读取整份 JSON；文件缺失/损坏/顶层非对象时返回 null（调用方据此
  /// 区分「文件不存在/损坏」与「存在但内容为空对象」，markers 首建
  /// 判定依赖该区分）；存在且可解析时返回 Map（可能为空 Map）。
  Future<Map<String, dynamic>?> readOrNull() async {
    final file = await _file;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// 读取整份 JSON；文件缺失/损坏/顶层非对象时返回空 Map。
  @override
  Future<Map<String, dynamic>> read() async => await readOrNull() ?? const {};

  /// 读取文件原始文本（不解析）；文件缺失/读失败返回 null。
  ///
  /// 供留档按**逐字节原文**另存：重编码
  /// 可能改键序/空白，等于没保住原件。
  Future<String?> readRawOrNull() async {
    final file = await _file;
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  /// 整份覆盖写入（tmp 写 + 原子重命名）。
  @override
  Future<void> write(Map<String, dynamic> json) {
    final run = _writeChain.then((_) => _write(json));
    // 写链吞掉错误防止后续任务卡死；错误由本次 write 的调用方承担。
    _writeChain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// 原子读改写：读 → [apply] → 写并入同一条写链串行执行（[apply] 可
  /// 异步，await 完成后才轮到链上下一任务，串行语义不变）。
  /// [apply] 未改动内容（编码结果与读入一致）时跳过写盘，不产生新 mtime。
  ///
  /// 链内读走 [readOrNull]：`present = false` 只表示「文件不在/损坏/顶层
  /// 非对象」，与「存在但内容为空对象」区分——不把两者塌缩成同一状态。
  @override
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) {
    final run = _writeChain.then((_) async {
      final raw = await readOrNull();
      final json = Map<String, dynamic>.of(raw ?? const {});
      final before = jsonEncode(json);
      await apply(json, present: raw != null);
      if (jsonEncode(json) == before) return;
      await _write(json);
    });
    _writeChain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// 删除底层文件与 `${file.path}.tmp` 残留；文件缺失视作已删、不抛错。
  /// 并入同一条写链（排在已排队的写之后），删除后本实例读回空态。
  Future<void> delete() {
    final run = _writeChain.then((_) async {
      final file = await _file;
      final tmp = File('${file.path}.tmp');
      if (await tmp.exists()) await tmp.delete();
      if (await file.exists()) await file.delete();
    });
    _writeChain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _write(Map<String, dynamic> json) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(file.path);
  }
}
