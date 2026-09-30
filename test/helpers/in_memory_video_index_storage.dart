import 'dart:async';

import 'package:dance_learning_app/persistence/video_index.dart';

/// 内存版视频索引存储（widget 测试用）。
///
/// [VideoIndexStore] 的真实文件 IO 在 flutter_test 的 fake async 时钟下
/// 不可完成（需 `tester.runAsync`），而镜像询问/历史应用的
/// widget 测试需要可控、确定性的索引读写；本实现以微任务完成
/// `load`/`update`，在 fake 时钟下可直接驱动。
class InMemoryVideoIndexStorage implements VideoIndexStorage {
  InMemoryVideoIndexStorage({VideoIndex initial = VideoIndex.empty})
      : _index = initial;

  VideoIndex _index;

  /// 当前内存索引（测试断言用）。
  VideoIndex get current => _index;

  /// `update` 被调用的次数（「不产生写盘」类断言用）。
  int updateCount = 0;

  /// `update` 回调实际改写索引的次数（返回原索引不计）。
  int mutationCount = 0;

  @override
  Future<VideoIndex> load() async => _index;

  @override
  Future<VideoIndex> update(
    FutureOr<VideoIndex> Function(VideoIndex current) mutate,
  ) async {
    updateCount += 1;
    final next = await mutate(_index);
    if (!identical(next, _index)) {
      mutationCount += 1;
      _index = next;
    }
    return _index;
  }
}
