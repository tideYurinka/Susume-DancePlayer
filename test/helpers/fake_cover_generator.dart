import 'package:dance_learning_app/dance/cover_cache.dart';
import 'package:dance_learning_app/dance/cover_generator.dart';

/// 记录生成调用并产出一份就绪缓存的封面生成替身（页面级用例用）。
///
/// 生成编排本身（命令装配 → 执行 → 原子替换）归
/// `test/dance/cover_generator_test.dart` 直测；页面只断言两件事——按预览线
/// 时刻调用生成、换封面时缓存先失效后重新生成。
class FakeCoverGenerator implements CoverGenerator {
  FakeCoverGenerator({required this.cache});

  final CoverCache cache;

  /// 按调用顺序记录的生成请求。
  final List<({String videoId, String sourcePath, Duration position})> calls =
      [];

  /// 生成结果：false = 取不到帧（不产出缓存），供失败路径用例。
  bool result = true;

  @override
  Future<bool> generate({
    required String videoId,
    required String sourcePath,
    required Duration position,
  }) async {
    calls.add((videoId: videoId, sourcePath: sourcePath, position: position));
    if (!result) return false;
    await cache.writeFrom(videoId, await cache.tempFileFor(videoId), position);
    return true;
  }
}
