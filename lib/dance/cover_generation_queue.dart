/// 封面取帧队列：卡片进入可见区才入队，**可见优先**
/// （先进入可见区的先取），同时最多两条任务，不阻塞滚动；完成后页面刷新
/// 对应卡片。导入路径不触本队列（惰性生成）。
///
/// 同一支舞**同一位置**只排队一次：重复请求复用同一结果，失败也在本会话内
/// 不再起第二次解码进程（与生成器的会话失败集同款，重启后可以再试一次）。
/// 位置是封面请求的身份——首线改了（封面位置随之改变）就是另一次请求，旧
/// 结果不能复用，否则卡片会拿旧位置的图当新封面。
library;

import 'dart:async';
import 'dart:collection';

/// 一次取帧请求（队列只依赖这三个值，不依赖卡片或页面）。
typedef CoverFrameRequest = ({
  String videoId,
  String sourcePath,
  Duration position,
});

/// 取帧执行端口：生产 = `CoverGenerator.generate`；测试注入内存替身。
typedef CoverFrameRunner = Future<bool> Function(CoverFrameRequest request);

/// 同时最多两条任务。
const int _kMaxConcurrentFrames = 2;

/// 请求身份：舞 + 位置（位置不同即另一次请求）。
String _requestKey(CoverFrameRequest request) =>
    '${request.videoId}@${request.position.inMilliseconds}';

/// 可见优先的小并发取帧队列。
class CoverGenerationQueue {
  CoverGenerationQueue({required this.run});

  final CoverFrameRunner run;

  final Queue<CoverFrameRequest> _pending = Queue<CoverFrameRequest>();
  final Map<String, Completer<bool>> _results = {};

  var _running = 0;

  /// 请求该舞在 [CoverFrameRequest.position] 处的封面；返回该位置当前是否
  /// 有封面。同一支舞同一位置的重复请求（页面重建、滚动回看）复用同一
  /// future，不会重复取帧。
  Future<bool> request(CoverFrameRequest request) {
    final existing = _results[_requestKey(request)];
    if (existing != null) return existing.future;
    final result = Completer<bool>();
    _results[_requestKey(request)] = result;
    _pending.add(request);
    _pump();
    return result.future;
  }

  void _pump() {
    while (_running < _kMaxConcurrentFrames && _pending.isNotEmpty) {
      final request = _pending.removeFirst();
      _running++;
      unawaited(
        Future<bool>.sync(() => run(request))
            .then((ready) => _settle(request, ready))
            .catchError((Object _) => _settle(request, false)),
      );
    }
  }

  void _settle(CoverFrameRequest request, bool ready) {
    _running--;
    _results[_requestKey(request)]!.complete(ready);
    _pump();
  }
}
