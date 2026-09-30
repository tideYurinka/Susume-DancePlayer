import 'dart:async';
import 'dart:convert';

import 'package:dance_learning_app/persistence/document_quarantine.dart';
import 'package:dance_learning_app/persistence/document_read_outcome.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';

/// 内存版按视频双文件存储（协调器测试用）。
///
/// 与 `InMemoryPrivateJsonStorage` / `InMemoryVideoIndexStorage` 同一先例：
/// 真实文件 IO 在 flutter_test 的 fake async 时钟下不可完成；本实现以微任务
/// 完成 load/save，接口与 [AtomicVideoDocumentStorage] 完全一致，协调器
/// 测试因此可以真实文件与内存 fake 双跑同一用例体。
///
/// 「何时留档」不复刻：本实现只提供一对内存内核，留档纪律交给
/// [QuarantiningVideoDocumentStorage]，与真实文件实现共用同一份。
class InMemoryVideoDocumentStorage implements VideoDocumentStorage {
  InMemoryVideoDocumentStorage({
    Map<String, dynamic> markers = const {},
    bool? markersPresent,
    Map<String, dynamic> local = const {},
    bool? localPresent,
  }) {
    final quarantined = <String, String>{};
    _quarantined = quarantined;
    _markers = _InMemoryDocumentKernel(
      content: markers,
      present: markersPresent ?? markers.isNotEmpty,
      documentName: 'markers_abc.json',
      quarantined: quarantined,
    );
    _local = _InMemoryDocumentKernel(
      content: local,
      present: localPresent ?? local.isNotEmpty,
      documentName: 'local_abc.json',
      quarantined: quarantined,
    );
    _storage = QuarantiningVideoDocumentStorage(
      markers: _markers,
      local: _local,
    );
  }

  late final QuarantiningVideoDocumentStorage _storage;
  late final _InMemoryDocumentKernel _markers;
  late final _InMemoryDocumentKernel _local;
  late final Map<String, String> _quarantined;

  /// 已留档的旁路文件：旁路文件名 → 原文（测试断言用）。
  Map<String, String> get quarantined => _quarantined;

  /// markers / local 各自的原子读改写链：并发 mutate 串行执行、互不覆盖
  /// （与 [AtomicVideoDocumentStorage] 经 `AtomicJsonFile.mutate` 得到的
  /// 语义一致）。链内读写经 [loadMarkers] / [saveMarkers] 虚派发，子类的
  /// 闸门 / 计数 / 失败覆写照常生效。
  Future<void>? _markersChain;
  Future<void>? _localChain;

  /// 模拟 markers 文件损坏：读兜底空态，[loadMarkersOrNull] 返回 null。
  void corruptMarkers() => _markers.markCorrupt();

  /// 当前 markers 文件内容深拷贝（测试断言用）。
  Map<String, dynamic> get markersSnapshot => _markers.snapshot;

  /// 当前 local 文件内容深拷贝（测试断言用）。
  Map<String, dynamic> get localSnapshot => _local.snapshot;

  @override
  Future<Map<String, dynamic>> loadMarkers() => _storage.loadMarkers();

  @override
  Future<Map<String, dynamic>?> loadMarkersOrNull() =>
      _storage.loadMarkersOrNull();

  @override
  Future<void> saveMarkers(Map<String, dynamic> json) =>
      _storage.saveMarkers(json);

  @override
  Future<Map<String, dynamic>> loadLocal() => _storage.loadLocal();

  @override
  Future<Map<String, dynamic>?> loadLocalOrNull() =>
      _storage.loadLocalOrNull();

  @override
  Future<void> saveLocal(Map<String, dynamic> json) =>
      _storage.saveLocal(json);

  @override
  Future<void> delete() => _storage.delete();

  @override
  Future<void> mutateMarkers(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) {
    final run = _enqueue(_markersChain, () => _mutateMarkers(apply));
    _markersChain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<void> mutateLocal(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) {
    final run = _enqueue(_localChain, () => _mutateLocal(apply));
    _localChain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// 排队到 [previous] 之后；无在途写时直接执行（不走 `.then`）。
  ///
  /// 空链不用「构造函数里建好的已完成 Future」承载：测试用例在 `setUp`
  /// （testWidgets 的 fake async 区之外）建实例，而写入发生在用例内——挂在
  /// 区外的 Future 上，回调不随 `pump` 推进，写会迟到到用例之后。首次写入
  /// 因此在调用方区里起链，后续写入接在它之后。
  static Future<void> _enqueue(
    Future<void>? previous,
    Future<void> Function() run,
  ) =>
      previous == null ? run() : previous.then((_) => run());

  Future<void> _mutateMarkers(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) async {
    // 链内读「最新」（虚派发：损坏态 / 闸门子类照常生效）并取存在位；
    // 拷成可变 Map（损坏态读出的空 Map 是常量）。
    final raw = await loadMarkersOrNull();
    final current = Map<String, dynamic>.of(raw ?? const {});
    final before = jsonEncode(current);
    await apply(current, present: raw != null);
    if (jsonEncode(current) == before) return; // 内容未变：跳写。
    await saveMarkers(current);
  }

  Future<void> _mutateLocal(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) async {
    final raw = await loadLocalOrNull();
    final current = Map<String, dynamic>.of(raw ?? const {});
    final before = jsonEncode(current);
    await apply(current, present: raw != null);
    if (jsonEncode(current) == before) return;
    await saveLocal(current);
  }
}

/// 单份文档的内存内核：内容与存在标志在这里，留档写进共享的 [quarantined]。
class _InMemoryDocumentKernel implements VideoDocumentStorageKernel {
  _InMemoryDocumentKernel({
    required Map<String, dynamic> content,
    required bool present,
    required this.documentName,
    required this.quarantined,
  })  : _content = Map.of(content),
        _present = present; // ignore: prefer_initializing_formals

  /// 旁路文件命名用的文档名。
  final String documentName;

  /// 已留档的旁路文件：旁路文件名 → 原文。
  final Map<String, String> quarantined;

  Map<String, dynamic> _content;
  bool _present;
  bool _corrupt = false;

  /// 当前内容深拷贝（测试断言用）。
  Map<String, dynamic> get snapshot =>
      jsonDecode(jsonEncode(_content)) as Map<String, dynamic>;

  /// 模拟文件损坏：读兜底空态，[readOrNull] 返回 null。
  void markCorrupt() {
    _corrupt = true;
    _present = false;
  }

  @override
  Future<Map<String, dynamic>?> readOrNull() async {
    if (!_present || _corrupt) return null;
    return jsonDecode(jsonEncode(_content)) as Map<String, dynamic>;
  }

  @override
  Future<String?> readRawOrNull() async {
    if (!_present || _corrupt) return null;
    return jsonEncode(_content);
  }

  @override
  Future<void> write(Map<String, dynamic> json) async {
    _content = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    _present = true;
    _corrupt = false;
  }

  @override
  Future<void> delete() async {
    _content = <String, dynamic>{};
    _present = false;
    _corrupt = false;
  }

  @override
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) async {
    final raw = await readOrNull();
    final current = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.of(raw);
    final before = jsonEncode(current);
    await apply(current, present: raw != null);
    if (jsonEncode(current) == before) return;
    await write(current);
  }

  @override
  Future<void> quarantine(String raw, DocumentReadOnlyReason reason) async {
    quarantined.putIfAbsent(
      DocumentQuarantine.sidecarName(documentName, raw, reason),
      () => raw,
    );
  }
}
