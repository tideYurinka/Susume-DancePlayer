/// 镜像域：全局镜像状态机、局部镜像总开关、镜像询问/历史
/// 提示浮层与无片段软门提示声明同处一库。
///
/// 依赖方向（单向，护栏钉住）：只依赖打开会话、导入索引、persistence 文档
/// 类型、提示/视觉 token 与本域浮层件；零 import 中枢，
/// 不 import 播放页与控制层。无片段软门提示声明与镜像状态机同库。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../persistence/video_index.dart';
import '../persistence/annotation_save_orchestrator.dart'
    show AnnotationSaveSeed, firstBuildSeeded;
import '../persistence/document_read_outcome.dart';
import '../persistence/marker_document.dart';
import '../persistence/video_document_store.dart';
import 'notice.dart' show NoticeId, NoticeSpec;
import '../core/notice_badge.dart';
import 'open_session.dart';
import 'visual_tokens.dart';

/// 镜像询问/历史应用阶段。
enum MirrorPhase {
  /// 无镜像交互：未打开、已作答，或历史提示已消失。
  idle,

  /// 首次打开：等待用户选择「是/否」。
  asking,

  /// 再次打开：已按历史应用镜像，正在展示「已按历史应用镜像」提示
  /// （无需确认，短暂展示后自动消失）。
  historyApplied,
}

/// 镜像状态机：首次打开询问、按 video_id 持久化、再次打开
/// 自动应用历史设置并提示。
///
/// - [resolve]：打开视频后消费打开会话给出的身份与条目（[videoId] 与
///   [entry]）——markers 存在 → 直接应用；否则 [entry] 命中且
///   [VideoIndexEntry.mirrorAsked]（已询问过）→ 立即应用到引擎并进入
///   [MirrorPhase.historyApplied]（提示「已按历史应用镜像」，无需确认）；
///   [entry] 缺失（会话无身份，或兜底补建没成）或未询问过 → 首次打开，
///   进入 [MirrorPhase.asking] 等待用户作答；
/// - [chooseMirrored]：用户作答（是/否）→ 立即应用到引擎（渲染层翻转，
///   不修改源文件字节），并按 video_id 持久化（同时标记「已询问」）；
///   条目由打开会话保证在册（按路径命中，或兜底定身份后补建），故作答
///   即写、不重试；
/// - 镜像为渲染层翻转：播放器页读取 [MirrorController.mirrored] 对画面
///   控件做水平 [Transform]，不触碰视频文件。
///
/// 身份来源：解析条目这一步交给打开会话——按路径命中即取条目身份、全程
/// 不读视频内容，查不到才兜底算一次并补建条目；本控制器不再自行按路径
/// 轮询索引、也不等任何后台摘要落盘。文档写入锚定会话给出的 videoId，
/// 首建初值只取会话给出的条目。
///
/// 镜像真值：公开标记文件为真值来源——打开会话建立基线时它已在盘
/// （[resolve] 的 `baselineMarkers`；含将来收到分享标记文件的场景）
/// → 直接应用两个镜像开关，不询问；打开时不存在则维持上述 index
/// `mirrorAsked` 逻辑。本次打开期间才首建的文档（首次导入的命名框以索引
/// 过渡值为种子）不在真值之列——命名答案不是镜像答案。作答 /
/// 控制层切换双写 index + markers（markers 不存在则按首建初值规则创建）。
///
/// 本控制器不持有索引的所有权；[dispose] 只取消提示倒计时。
///
/// 镜像两层开关：本控制器同时管**全局镜像**
/// （[mirrored]，整片开关）与**局部镜像**总开关
/// （[localMirrorEnabled]，回答"要不要按片段集合把部分区间反相"）。两个
/// 字段的落盘路径与生命周期逐点相同——打开视频时读、切换时双写 markers +
/// index、markers 不存在时按首建初值规则创建、markers 为真值时回写 index
/// 缓存；拆成两个控制器等于把同一条管线写两遍。
///
/// 局部镜像总开关是**视图开关**：真值在公开标记文件的 `meta` 段（随分享
/// 迁移），切换即写盘、不入撤销/重做史、不受锁定分段门禁。渲染层与顶栏
/// 不直接读文件——控制器把每次取值经 [onLocalMirrorEnabledChanged] 推给
/// 会话值道（写缝），由值道喂给合成与槽位视觉。
class MirrorController extends ChangeNotifier {
  MirrorController(
    this._indexStore, {
    this.coordinatorFor,
    this.onLocalMirrorEnabledChanged,
    this.onWriteRejected,
    this.hintDuration = const Duration(seconds: 2),
  });

  final VideoIndexStorage _indexStore;

  /// 按视频文档协调器工厂（family 参数 = videoId）。null = 未按视频接好
  /// 持久化的环境只走 index（零增量的测试环境，先例同
  /// `SongSignatureController.coordinatorFor`）。videoId 由打开会话给出。
  final VideoDocumentCoordinator? Function(String videoId)? coordinatorFor;

  /// 局部镜像总开关的会话值道写缝：每次取值变化（打开读取、用户切换、
  /// 恢复兜底）推送给宿主，由宿主写进总开关值道。null = 无值道的环境
  /// （控制器直测）只落在控制器自身。
  final ValueChanged<bool>? onLocalMirrorEnabledChanged;

  /// markers 写回被拒（只读文档 / 读与写之间换成只读文件）的呈现缝：
  /// 装配处接到既有短暂提示通道。null = 无提示环境（控制器直测）。
  final void Function()? onWriteRejected;

  /// 「已按历史应用镜像」提示的展示时长（随后自动消失）。
  final Duration hintDuration;

  MirrorPhase _phase = MirrorPhase.idle;
  bool _mirrored = false;
  bool _localMirrorEnabled = true;
  String? _filePath;

  /// 打开会话给出的已确认身份（镜像读写都锚定它，不各自解析索引条目）。
  String? _videoId;

  /// 会话给出的条目（打开路径按路径命中，或兜底定身份后补建；会话无身份
  /// 或兜底没补建成时为 null）：镜像历史判定与首建初值只读它——无条目时按
  /// 新视频缺省，不套用任何旧条目。
  VideoIndexEntry? _entry;
  Timer? _hintTimer;
  bool _disposed = false;

  /// 当前阶段（widget 据此显隐询问弹窗/历史提示）。
  MirrorPhase get phase => _phase;

  /// 当前应用的镜像状态（播放器页据此对画面做水平翻转）。
  bool get mirrored => _mirrored;

  /// 局部镜像总开关当前值（顶栏「局部镜像」槽的琥珀态、合成输入之一）。
  bool get localMirrorEnabled => _localMirrorEnabled;

  /// 打开视频成功后调用：消费打开会话给出的身份与条目（[videoId] 与
  /// [entry]），不再自行轮询索引条目。
  ///
  /// [videoId] 为 null（会话无身份：兜底摘要失败 / 文档不可读）→ 保持默认
  /// （不询问、不提示），不阻塞播放。
  ///
  /// 打开时公开标记文件已在盘 → 直接应用它两个镜像开关（不询问、不看
  /// index 过渡值；含将来收到分享标记文件的场景），并按同步规则把两个开关
  /// 回写 index 缓存；不在盘则 [entry] 命中且「已询问过」→ 立即应用 index
  /// 历史设置并提示「已按历史应用镜像」；[entry] 缺失或未询问过 → 首次
  /// 打开，进入询问阶段（无条目时按新视频语义，不套用旧条目）。
  ///
  /// [baselineMarkers] = 打开会话建立基线时公开标记文件**在盘**的内容
  /// （`OpenSession.markersOnDisk`，唯一基线）；null = 打开时不存在（或
  /// 损坏不可读）。传 null 时按 [entry] 的 `mirrorAsked` 逻辑判首次 / 历史：
  /// 首次导入的命名框会在本次打开期间首建文档（以索引过渡值为种子），它
  /// 不在此列——命名答案不是镜像答案，用户仍须被问。
  Future<void> resolve(
    String filePath, {
    required String? videoId,
    VideoIndexEntry? entry,
    required MarkersDocument? baselineMarkers,
  }) async {
    if (_phase != MirrorPhase.idle || _disposed) return;
    _filePath = filePath;
    _videoId = videoId;
    _entry = entry;
    // 换视频/重开兜底：总开关先复位到缺省（真值由下方三条读取路径给出），
    // 无身份时不得串入上一视频的取值。
    _applyLocalMirrorEnabled(true);
    if (videoId == null) return;

    // 镜像真值：基线里 markers 在盘 → 直接应用两个镜像开关
    // （不询问、不看 index 过渡值；含分享标记文件与「打开时已在盘」的新建
    // 文档），并按同步规则把两个开关回写 index 缓存。
    if (baselineMarkers != null) {
      _mirrored = baselineMarkers.mirrored;
      _applyLocalMirrorEnabled(baselineMarkers.localMirrorEnabled);
      _phase = MirrorPhase.idle;
      notifyListeners();
      unawaited(_writeBackIndexMirror(filePath, baselineMarkers));
      return;
    }

    if (entry == null || !entry.mirrorAsked) {
      // 首次打开：无条目或条目未标记「已询问」（用户不会被漏问）。
      _phase = MirrorPhase.asking;
      notifyListeners();
      return;
    }
    _mirrored = entry.mirrored;
    // 本机缓存过渡值（markers 尚未创建的首次导入；缺键兜底 true）。
    _applyLocalMirrorEnabled(entry.localMirrorEnabled);
    _phase = MirrorPhase.historyApplied;
    _hintTimer = Timer(hintDuration, _dismissHint);
    notifyListeners();
  }

  /// 打开视频后调用：由本域消费打开会话给出的身份与文档快照（[OpenSession]
  /// 的 filePath / videoId / entry / markersOnDisk），语义与 [resolve] 逐点
  /// 相同（见其文档）。宿主把会话整份交给本域即可。
  Future<void> resolveFor(OpenSession session) => resolve(
    session.filePath,
    videoId: session.videoId,
    entry: session.entry,
    baselineMarkers: session.markersOnDisk,
  );

  /// 局部镜像总开关切换（顶栏槽点击）：立即生效并落盘（无「保存」步）。
  ///
  /// 视图开关语义：不进撤销/重做史、不受锁定分段门禁（门禁在装配层就不
  /// 过问本槽）。写盘走与全局镜像逐点相同的通路——双写 index + markers、
  /// 写失败静默（值道已更新，下次打开仍可恢复）。
  void setLocalMirrorEnabled(bool value) {
    if (_disposed || value == _localMirrorEnabled) return;
    _applyLocalMirrorEnabled(value);
    notifyListeners();
    final filePath = _filePath;
    if (filePath != null) {
      unawaited(_persistLocalMirrorEnabled(filePath, value));
    }
  }

  /// 从创建入口新建片段时的「创建即生效」：总开关关着才自动打开
  /// 并写盘，开着则无动作（不产生多余的写盘与通知）。
  void enableLocalMirrorForNewFragment() {
    if (_disposed || _localMirrorEnabled) return;
    setLocalMirrorEnabled(true);
  }

  /// 用户作答（是/否）：立即应用到引擎（渲染层翻转），并按 video_id
  /// 持久化到索引（同时标记「已询问」；条目由打开会话保证在册，故作答即写）。
  Future<void> chooseMirrored(bool value) async {
    if (_disposed) return;
    _mirrored = value;
    _phase = MirrorPhase.idle;
    notifyListeners();
    final filePath = _filePath;
    if (filePath != null) {
      unawaited(_persist(filePath, value));
    }
  }

  /// 按 [filePath] 找到索引条目写镜像作答（同时标记「已询问」）。
  /// markers 写入锚定会话给出的 [MirrorController._videoId]。
  Future<void> _persist(String filePath, bool value) => _persistThrough(
    filePath,
    // 作答按 video_id 存取并标记「已询问」；该标记就位才算条目可用。
    writeIndex: (index) =>
        index.setMirrorAnswerByFilePath(filePath, mirrored: value),
    entryReady: (entry) => entry.mirrorAsked,
    writeMarkers: () => _patchMarkers((seeded) => seeded.withMirrored(value)),
    failureLog: '镜像状态持久化失败',
  );

  /// 局部镜像总开关的落盘：与 [_persist] 逐点相同的通路——先把
  /// 过渡值写进 index 缓存，条目在册即双写 markers。写失败静默（值道已更新，
  /// 下次打开仍可恢复）。
  Future<void> _persistLocalMirrorEnabled(String filePath, bool value) =>
      _persistThrough(
        filePath,
        writeIndex: (index) => index.setLocalMirrorEnabledByFilePath(
          filePath,
          localMirrorEnabled: value,
        ),
        // 总开关与「已询问」标记无关：条目存在即可双写。
        entryReady: (_) => true,
        writeMarkers: () =>
            _patchMarkers((seeded) => seeded.withLocalMirrorEnabled(value)),
        failureLog: '局部镜像总开关持久化失败',
      );

  /// 两个镜像开关共用的落盘通路：写 index 过渡值，条目在册即写 markers；
  /// 写失败静默（内存态已更新，下次打开仍可恢复），不抛到 UI。
  ///
  /// 不做「条目未落盘就等它落盘」的重试：条目由打开会话保证在册（按路径
  /// 命中，或兜底定身份后补建），作答时按路径必能找到它。
  ///
  /// 索引条目按路径取，但只在条目身份与会话给出的身份一致时才写（身份不符
  /// 时旧条目保留、不被写）；身份不符时索引没有可写目标，答案直接落新身份
  /// 文档。
  Future<void> _persistThrough(
    String filePath, {
    required VideoIndex Function(VideoIndex index) writeIndex,
    required bool Function(VideoIndexEntry entry) entryReady,
    required Future<void> Function() writeMarkers,
    required String failureLog,
  }) async {
    if (_disposed) return;
    final videoId = _videoId;
    try {
      final index = await _indexStore.update((current) {
        final existing = current.findByFilePath(filePath);
        if (existing != null &&
            videoId != null &&
            existing.videoId != videoId) {
          return current; // 身份不符：旧条目保留，不被写。
        }
        return writeIndex(current);
      });
      final entry = index.findByFilePath(filePath);
      if (entry != null && videoId != null && entry.videoId != videoId) {
        // 身份不符：索引没有本文档的条目，答案只落新身份文档。
        unawaited(writeMarkers());
        return;
      }
      if (entry != null && entryReady(entry)) {
        unawaited(writeMarkers());
      }
    } on Object catch (error) {
      debugPrint('$failureLog：$error');
    }
  }

  /// 两个开关共用的 markers 字段级 patch：首建立底（不触碰已存在文件的现值，
  /// 初值取索引的署名缓存 + 两个开关的过渡值）→ 写本次真值。首建判定在
  /// 协调器串行写链内进行，不受并发首写竞态影响；写失败静默（index 过渡值
  /// 兜底，不阻塞 UI）。
  ///
  /// 文档寻址与首建初值都取会话给出的身份与条目（[MirrorController._videoId]
  /// / [MirrorController._entry]）：无条目时按新视频缺省，不套用旧条目。
  Future<void> _patchMarkers(
    MarkersDocument Function(MarkersDocument seeded) patch,
  ) async {
    if (_disposed) return;
    final videoId = _videoId;
    if (videoId == null) return;
    try {
      final coordinator = coordinatorFor?.call(videoId);
      if (coordinator == null) return;
      final entry = _entry;
      final outcome = await coordinator.readMarkersOutcome();
      if (outcome is DocumentReadOnly<MarkersDocument>) {
        onWriteRejected?.call();
        return;
      }
      if (outcome is! WritableDocumentReadOutcome<MarkersDocument>) return;
      final result = await outcome.write((context) {
        final seeded = firstBuildSeeded(
          context.document,
          present: context.present,
          seed: AnnotationSaveSeed.fromEntry(entry),
        );
        return patch(seeded);
      });
      if (result is DocumentWriteRejected<MarkersDocument>) {
        onWriteRejected?.call();
      }
    } on Object {
      // markers 写失败静默：index 过渡值兜底，下次打开仍可恢复。
    }
  }

  /// markers 真值回写 index 两个镜像缓存（同步规则，不触碰
  /// 「已询问」标记）；索引条目身份与会话给出的身份不同时不回写旧条目。
  /// 失败静默。
  Future<void> _writeBackIndexMirror(
    String filePath,
    MarkersDocument markers,
  ) async {
    final videoId = _videoId;
    try {
      await _indexStore.update((index) {
        final entry = index.findByFilePath(filePath);
        if (entry == null || (videoId != null && entry.videoId != videoId)) {
          return index;
        }
        return index
            .setMirroredByFilePath(filePath, mirrored: markers.mirrored)
            .setLocalMirrorEnabledByFilePath(
              filePath,
              localMirrorEnabled: markers.localMirrorEnabled,
            );
      });
    } on Object {
      // 回写失败不影响本次打开（markers 仍是真值来源）。
    }
  }

  /// 写入会话值道的局部镜像总开关现值（写缝；无值道的环境为空操作）。
  void _applyLocalMirrorEnabled(bool value) {
    _localMirrorEnabled = value;
    onLocalMirrorEnabledChanged?.call(value);
  }

  void _dismissHint() {
    _hintTimer = null;
    if (_phase != MirrorPhase.historyApplied || _disposed) return;
    _phase = MirrorPhase.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hintTimer?.cancel();
    _hintTimer = null;
    super.dispose();
  }
}

/// 无片段软门提示声明：一行声明 = 身份 + 内容 +
/// 定位 key。触发面由提示模块持有（控制层经 `noticeTriggerProvider(
/// NoticeId.localMirrorEmpty)` 只报身份）；挂载由演出层的唯一宿主承担。
/// 提示纯视觉：不产生任何状态变化、不入撤销史。
Widget localMirrorEmptyNoticeContent(BuildContext _) =>
    const Text('请添加局部镜像片段', style: kNoticeTextStyle);

/// 无片段软门提示声明清单项（组合根装配）。
const localMirrorEmptyNoticeSpec = NoticeSpec(
  id: NoticeId.localMirrorEmpty,
  content: localMirrorEmptyNoticeContent,
  noticeKey: Key('local_mirror_empty_prompt'),
);

/// 镜像询问/历史提示覆盖层。
///
/// 必须作为 [Stack] 的子级使用（自身返回 [Positioned]）：
/// - [MirrorPhase.asking]：全屏遮罩 + 居中「需要镜像吗？」两栏依据大按钮卡
///   （左「不需要镜像」/ 右「需要镜像」），模态——不选择不消失，遮罩点击
///   不关闭；卡片超出屏高 − 上下留边时在卡片内部滚动；
/// - [MirrorPhase.historyApplied]：顶部居中「已按历史应用镜像」提示
///   （不拦截触摸，由控制器倒计时自动消失）；
/// - 其余阶段不占空间。
class MirrorOverlay extends StatelessWidget {
  const MirrorOverlay({super.key, required this.controller});

  final MirrorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.phase) {
          case MirrorPhase.asking:
            return Positioned.fill(
              key: const Key('mirror_question_scrim'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 模态询问：点遮罩不关闭，必须作答。
                onTap: () {},
                child: ColoredBox(
                  color: Colors.black54,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Center(
                        child: ConstrainedBox(
                          // 适配兜底：气泡在屏内居中，最大高 = 屏高 − 上下留边，
                          // 超出时卡片内部滚动（横屏 + 系统大字号是唯一会顶到
                          // 的情况）。
                          constraints: BoxConstraints(
                            maxWidth:
                                constraints.maxWidth -
                                2 * kNoticeCardScreenInsetH,
                            maxHeight:
                                constraints.maxHeight -
                                2 * kNoticeCardScreenInsetV,
                          ),
                          child: _QuestionCard(
                            onYes: () => controller.chooseMirrored(true),
                            onNo: () => controller.chooseMirrored(false),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          case MirrorPhase.historyApplied:
            return Positioned(
              key: const Key('mirror_history_hint'),
              top: 48,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: const NoticeBadge(
                    child: Text('已按历史应用镜像', style: kNoticeTextStyle),
                  ),
                ),
              ),
            );
          case MirrorPhase.idle:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

/// 首次打开的镜像询问卡片：标题 + 副标题 + 左右两栏依据大按钮。
///
/// 左栏 = 不需要镜像（[onNo]）、右栏 = 需要镜像（[onYes]），次序固定；两栏
/// 等权等高、无推荐位。整栏是可点面（按下有水波）。内容超出气泡最大高时在
/// 气泡内部滚动。
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.onYes, required this.onNo});

  final VoidCallback onYes;
  final VoidCallback onNo;

  /// 左栏「不需要镜像」的适用场景（逐字）。
  static const List<String> _noItems = [
    '视频来源已经镜像过了',
    '标题有“镜像”“镜面”的字样',
    '大多数舞蹈教程视频',
    '从背面拍摄的练习视频',
  ];

  /// 右栏「需要镜像」的适用场景（逐字）。
  static const List<String> _yesItems = ['没有镜像处理过的原始视频', '正片、舞台、练习室、比赛等作品'];

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(kNoticeCardRadius);
    return Container(
      decoration: BoxDecoration(
        gradient: kNoticeCardGradient,
        borderRadius: radius,
        boxShadow: const [kNoticeCardShadow],
      ),
      // 描边画在内容之上（内部滚动时内容会到卡片边缘）。
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: kNoticeCardBorderColor),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(kNoticeCardPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '需要镜像吗？',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: kNoticeCardTitleColor,
                    fontSize: kNoticeCardTitleSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: kNoticeCardTitleGap),
                const Text(
                  '对于正面拍摄的视频，总共需要一次镜像处理，就能像照镜子一样直接学',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: kNoticeCardSubtitleColor,
                    fontSize: kNoticeCardSubtitleSize,
                    height: kNoticeCardSubtitleLineHeight,
                  ),
                ),
                const SizedBox(height: kNoticeCardSubtitleGap),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ChoiceColumn(
                          choiceKey: const Key('mirror_no_button'),
                          title: '不需要镜像',
                          items: _noItems,
                          onTap: onNo,
                        ),
                      ),
                      const SizedBox(width: kNoticeCardColumnGap),
                      Expanded(
                        child: _ChoiceColumn(
                          choiceKey: const Key('mirror_yes_button'),
                          title: '需要镜像',
                          items: _yesItems,
                          onTap: onYes,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 询问卡的一栏大按钮：栏标题（居中）/ 1dp 横线 / 逐条「·」依据。
///
/// 整栏是可点面（[InkWell] 水波）；两栏等宽由父 [Row] 的 [Expanded] 给出，
/// 等高由 [IntrinsicHeight] + [CrossAxisAlignment.stretch] 给出。
class _ChoiceColumn extends StatelessWidget {
  const _ChoiceColumn({
    required this.choiceKey,
    required this.title,
    required this.items,
    required this.onTap,
  });

  final Key choiceKey;
  final String title;
  final List<String> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(kNoticeCardColumnRadius);
    return ClipRRect(
      borderRadius: radius,
      child: Material(
        color: kNoticeCardColumnColor,
        child: InkWell(
          key: choiceKey,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: kNoticeCardColumnBorderColor),
            ),
            padding: kNoticeCardColumnPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kNoticeCardColumnTitleColor,
                    fontSize: kNoticeCardColumnTitleSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: kNoticeCardDividerMargin,
                  ),
                  child: Container(height: 1, color: kNoticeCardDividerColor),
                ),
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: kNoticeCardItemGap),
                  _ChoiceItem(text: items[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 询问卡的一条适用场景：「·」占固定列宽 + 文本；文本折行时第二行与首行
/// 文字左缘对齐（文本在 [Expanded] 内换行，不缩到点下面）。
class _ChoiceItem extends StatelessWidget {
  const _ChoiceItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: kNoticeCardDotWidth,
          child: Text(
            '·',
            style: TextStyle(
              color: kNoticeCardDotColor,
              fontSize: kNoticeCardItemSize,
              height: kNoticeCardItemLineHeight,
            ),
          ),
        ),
        const SizedBox(width: kNoticeCardDotGap),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: kNoticeCardItemColor,
              fontSize: kNoticeCardItemSize,
              height: kNoticeCardItemLineHeight,
            ),
          ),
        ),
      ],
    );
  }
}
