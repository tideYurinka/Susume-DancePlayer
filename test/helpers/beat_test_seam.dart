import 'dart:async';

import 'package:dance_learning_app/beat/beat_pipeline.dart'
    show BeatAnalysisPipeline, BeatAnalysisRequest;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/beat_prompt_panel.dart'
    show beatPromptEnabledProvider;
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自动首尾测试 seam：控制层与播放页 widget 测试共用的节拍
/// 轨三态注入工具——挂起管线 + 就绪态样例 + 状态注入。

/// 就绪节拍轨状态样例：真实网格拍点 0.5/1.0/1.5/2.0s——末拍 2.0s 不在
/// 四拍格点（格点 = 0.5s 起每 4 拍），可断言自动首尾按拍点首末落位、
/// 不吸附挪动。
BeatTrackState readyBeatState() => BeatTrackState.ready(
  marker_doc.BeatGrid(
    model: 'fake.onnx',
    fps: 100,
    generatedAt: DateTime.utc(2024),
    beats: const [
      marker_doc.BeatPoint(t: 0.5, down: true),
      marker_doc.BeatPoint(t: 1.0, down: false),
      marker_doc.BeatPoint(t: 1.5, down: false),
      marker_doc.BeatPoint(t: 2.0, down: false),
    ],
  ),
);

/// 与占位均匀网格同值的就绪态样例（分段八拍点/分段工具就绪门
/// 用）：拍点每 0.5s 一拍、强拍每 4 拍（与 placeholderBeatGrid 逐位一致，
/// 覆盖 [seconds]）→ 八拍点 = 0/4/8…s。就绪门测试注入本态即可复用既有
/// 占位网格几何换算。
BeatTrackState uniformReadyBeatState({double seconds = 30}) {
  // 含端点拍 t = seconds（与无界占位网格在整片窗口内的拍数一致）。
  final count = (seconds / 0.5).round() + 1;
  return BeatTrackState.ready(
    marker_doc.BeatGrid(
      model: 'fake.onnx',
      fps: 100,
      generatedAt: DateTime.utc(2024),
      beats: [
        for (var i = 0; i < count; i++)
          marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
      ],
    ),
  );
}

/// 就绪但拍点为空态样例（行为修正缝）：beat 段存在、拍点列表
/// 为空——App 自身写入路径产不出（只有手改或分享来的标记文件会有）；
/// 真实拍点可用谓词须判其不可用，占位均匀节奏不得冒充真实网格。
BeatTrackState readyEmptyBeatsBeatState() =>
    BeatTrackState.ready(
      marker_doc.BeatGrid(
        model: 'fake.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2024),
      ),
    );

/// 就绪态均匀网格文档：拍点每 0.5s 一拍、强拍每 4 拍（4/4 均匀，
/// 强拍序号 0/4/8…、时刻 0/2/4…s）；可选八拍锚点（拍序号数组）。
/// 覆盖 [seconds] 秒（含端点拍）。
marker_doc.BeatGrid uniformDownbeatGridDoc({
  double seconds = 30,
  List<int> anchors = const [],
}) {
  final count = (seconds / 0.5).round() + 1;
  return marker_doc.BeatGrid(
    model: 'fake.onnx',
    fps: 100,
    generatedAt: DateTime.utc(2024),
    anchors: anchors,
    beats: [
      for (var i = 0; i < count; i++)
        marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
    ],
  );
}

/// 就绪态均匀网格（同上文档，包成节拍轨三态）。
BeatTrackState uniformDownbeatBeatState({
  double seconds = 30,
  List<int> anchors = const [],
}) => BeatTrackState.ready(
  uniformDownbeatGridDoc(seconds: seconds, anchors: anchors),
);

/// 永不完成的节拍分析管线：无 Timer、不产结果——打开恢复流程停稳在
/// 占位态且无待决定时器，目标态随后经 [injectBeatState] 注入。
class HangingBeatPipeline implements BeatAnalysisPipeline {
  const HangingBeatPipeline();

  @override
  Future<List<marker_doc.BeatPoint>> analyze(
    BeatAnalysisRequest request,
  ) => Completer<List<marker_doc.BeatPoint>>().future;
}

/// 挂起管线共享实例。
const hangingBeatPipeline = HangingBeatPipeline();

/// 打开恢复流程停稳（pumpPlayer 完成后）注入节拍轨状态：管线挂起，
/// 注入态不再被分析流程改写。
Future<void> injectBeatState(WidgetTester tester, BeatTrackState state) async {
  ProviderScope.containerOf(
    tester.element(find.byType(PlayerPage)),
    listen: false,
  ).read(beatTrackStateProvider.notifier).replace(state);
  await tester.pump();
}

/// 节拍动画总开关置开（默认关）：数拍浮层/准备期数字类 widget
/// 用例钉的是浮层机制本身，布景挂页后调用本 helper 置开；「默认关」「关 →
/// 不挂载」仍由各用例自行断言或显式关闭覆盖。
void turnBeatAnimationOn(WidgetTester tester) {
  ProviderScope.containerOf(
    tester.element(find.byType(PlayerPage)),
    listen: false,
  ).read(beatPromptEnabledProvider.notifier).set(true);
}
