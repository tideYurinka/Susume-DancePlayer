/// 备注编辑器输入条：横屏下**一条横排**——
/// `输入框 | 舞者快捷区 | 名册 | 删除 | 完成`。颜色色板 / 描边开关 /
/// 最近样式三枚钮都带文字（不靠图标猜）。
///
/// **竖屏两行**：上行
/// 输入框满宽（仍单行 / 自动聚焦 / 回车不换行），下行动作区一排——舞者
/// 快捷区、名册、删除、完成。361dp 宽下横排会把输入框挤到零宽，把快捷区
/// 移出上行后它也随之从 260dp 上限里解放、由 [Expanded] 占满动作行剩余宽，
/// 条内横向滚动照旧。横屏形态逐位不变。
///
/// **名册态原地换装**：点「名册」钮不另开面、
/// 不弹面板——左段备注输入框**原地**换成舞者输入框（右侧多一枚「新建」）、
/// 钮文案变「返回备注编辑」。舞者输入框**回车**与「新建」同一条新建路径：
/// 只建人、不自动把点名写进备注；建完**立刻弹 24 色选色浮层**（那期间
/// 键盘收起），选完 / 取消 / 删除后浮层关闭、焦点交回舞者输入框，可连续
/// 输入下一个名字——颜色不再「新建时先写死一个」。再点「返回备注编辑」
/// 回备注态，已打的备注文本原样保留。
///
/// **键盘感知停靠**：键盘升起时整条输入条**位移**
/// 到键盘上沿之上（取数经 [WindowMetricsWatcher] 共用件；播放页
/// `resizeToAvoidBottomInset: false`，只能读窗口真实 inset）；键盘收起回
/// 到底部原位——形态不变、只是位移。停靠位**逐帧跟随当前 inset**：键盘
/// 升起是逐帧到达的动画，跟随当前值才停在最终上沿之外；变高变矮同样跟随。
/// 停靠只在呈现层、不涉任何持久化状态。输入条高于键盘上方的安全空间时
/// 呈现层**临时缩小**到放得下、退出编辑恢复。
///
/// **舞者快捷区**：这一行中段的
/// 一排舞者词条——备注态点词条在光标处写下 `@名字 `、名册态点词条给这位
/// 舞者选代表色。名册态没有长按管理与「＋ 新建」。
///
/// **收起即存**（文本经标注编辑模块的 [SetNoteText] 命令提交，净变化才
/// 发起）；删除经 [RemoveNote]（入史，不受锁定分段管——锁只护分段结构）。
/// **归一国空即删**：收起时文本 trim 后为空 → 不写文本、改提交 [RemoveNote]
/// ——空文本不是可保存状态，「添加」条目建出备注后一个字没写就收起也不留
/// 片段。
/// 编辑中的目标以备注 [NoteSticker.startMs] 标识（列表按起点升序、文本
/// 编辑不改窗，起点在编辑器存续期稳定）；落点被占的转编辑路由归。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/note_sticker.dart';
import '../help/content_registry.dart'
    show badgeRosterUnitId, rosterButtonAnchorKey;
import '../help/guide_anchor.dart' show GuideAnchor, GuideBadgeTrigger;
import 'annotation_edit.dart';
import 'annotation_editor.dart';
import 'dancer_roster_chips.dart';
import 'dancer_roster_controller.dart';
import 'visual_tokens.dart';
import 'window_keyboard_metrics.dart';

/// 录入期单行化 formatter：回车与粘贴进来的换行当场归一为
/// 空格，输入框里永远看不到换行；收口点仍是 [normalizeNoteText]
/// （提交前再归一，双保险）。
class NoteSingleLineFormatter extends TextInputFormatter {
  const NoteSingleLineFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = normalizeNoteText(newValue.text);
    if (text == newValue.text) return newValue;
    // 归一使文本变短（每个换行缩 1），选区偏移同步钳回新文本域内，
    // composing 区一并清空——避免越界断言与光标错位。
    final selection = newValue.selection;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: selection.extentOffset.clamp(0, text.length),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
    );
  }
}

/// 正在编辑文本的备注（[NoteSticker.startMs] 标识）；null = 编辑器收起。
final noteTextEditorTargetProvider =
    NotifierProvider<NoteTextEditorTarget, int?>(NoteTextEditorTarget.new);

class NoteTextEditorTarget extends Notifier<int?> {
  @override
  int? build() => null;

  /// 以备注起点打开编辑器（重复打开即切换目标）。
  void open(int startMs) => state = startMs;

  /// 收起（不提交——提交由面板收起动作负责）。
  void close() => state = null;
}

/// 定位高亮的备注片段（[NoteSticker.startMs] 标识；null = 无）：
/// 贴纸左下角工具跳转控制层时由宿主打上，轨道行给对应备注片段渲染高亮
/// 标识；片段被点按 / 拖动起手即清（用户已到位）。
final noteFragmentHighlightProvider =
    NotifierProvider<NoteFragmentHighlight, int?>(NoteFragmentHighlight.new);

class NoteFragmentHighlight extends Notifier<int?> {
  @override
  int? build() => null;

  /// 打高亮（重复打同一片段幂等）。
  void highlight(int startMs) => state = startMs;

  /// 清高亮；无高亮时幂等。
  void clear() => state = null;
}

/// 备注编辑器输入条：挂播放页 Stack 顶层（控制层之上），目标非空时显示。
class NoteTextEditorPanel extends ConsumerStatefulWidget {
  const NoteTextEditorPanel({super.key});

  @override
  ConsumerState<NoteTextEditorPanel> createState() =>
      _NoteTextEditorPanelState();
}

class _NoteTextEditorPanelState extends ConsumerState<NoteTextEditorPanel> {
  final TextEditingController _controller = TextEditingController();

  /// 舞者输入框（名册态左段）与它的焦点（选色浮层关闭后焦点交回，
  /// 可连续输入下一个名字）。
  final TextEditingController _dancerController = TextEditingController();
  final FocusNode _dancerFocus = FocusNode();

  /// 名册态（呈现层换装）：true = 左段是舞者输入框。编辑器收起
  /// 即回备注态，不跨目标残留。
  bool _rosterMode = false;

  /// 空白舞者名的内联提示：非 null = 提示在场；输入变化即清，
  /// 编辑器收起不留残留。
  String? _dancerHint;

  /// 清内联提示（已是空态则不动、不空转重建）。
  void _clearDancerHint() {
    if (_dancerHint != null) setState(() => _dancerHint = null);
  }

  /// 已同步进文本框的目标（目标切换即重置文本框内容）。
  int? _syncedTarget;

  /// 呈现层临时缩小系数（输入条高于安全带时 < 1；退出编辑恢复 null）。
  double? _shrinkScale;

  /// 缩小量测回调的在途守卫（同帧多次构建只排一次回调）。
  bool _shrinkCheckPending = false;

  /// 停靠内容（输入条本体）量测锚点：供临时缩小的尺寸判定。
  final GlobalKey _dockContentKey = GlobalKey();

  @override
  void dispose() {
    _controller.dispose();
    _dancerController.dispose();
    _dancerFocus.dispose();
    super.dispose();
  }

  /// 按目标起点定位备注（下标 + 条目，一处声明两处共用）；找不到返回
  /// null（目标已失效——备注被撤销/删除等）。
  (int, NoteSticker)? _locate(int? startMs) {
    if (startMs == null) return null;
    final notes = ref.read(noteStickersProvider);
    final index = notes.indexWhere((note) => note.startMs == startMs);
    if (index < 0) return null;
    return (index, notes[index]);
  }

  /// 收起即存：文本有净变化才提交（同文本提交由模块判 no-op，此处不发起）；
  /// 提交载荷经 [normalizeNoteText] 归一（进模块前换行归一为空格，
  /// 存盘文本不含换行）；目标已失效（备注被删等）只收起不提交。
  ///
  /// 归一国空即删：trim 后为空 → 提交既有 [RemoveNote] 而不是写空文本
  /// （空文本不是可保存状态，删除是既定语义）；删除是
  /// 一个撤销步，撤销即恢复整条备注连同原文本。
  void _collapse() {
    final located = _locate(ref.read(noteTextEditorTargetProvider));
    final text = normalizeNoteText(_controller.text);
    if (located != null) {
      final editor = ref.read(annotationEditorProvider);
      if (text.trim().isEmpty) {
        editor.submit(RemoveNote(index: located.$1));
      } else if (located.$2.text != text) {
        // 载荷 = 纯文本本身（不解析点名、不读名册、不存引用）。
        editor.submit(SetNoteText(index: located.$1, text: text));
      }
    }
    ref.read(noteTextEditorTargetProvider.notifier).close();
  }

  /// 点名插入：把 `@名字 `（含尾随空格）写进文本框**光标处**
  /// ——不是追加到末尾；写后光标停在插入单元之后（连续点名顺手）。
  /// 与打字同语义：有选区时替换选区。无有效光标（从未聚焦等）时落在
  /// 文本末尾。
  void _insertDancerMention(String name) {
    final value = _controller.value;
    final selection = value.selection;
    final hasRange =
        selection.start >= 0 && selection.end >= 0 && selection.isValid;
    final start = hasRange ? selection.start : value.text.length;
    final end = hasRange ? selection.end : value.text.length;
    final token = '@$name ';
    _controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(
        offset: start < end ? start : start + token.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(noteTextEditorTargetProvider);
    // 备注列表随行（目标备注被撤销/删除时面板即时收起，不残留空面板）。
    final notes = ref.watch(noteStickersProvider);
    final index = target == null
        ? -1
        : notes.indexWhere((n) => n.startMs == target);
    final note = index < 0 ? null : notes[index];
    if (target != _syncedTarget) {
      _syncedTarget = target;
      _controller.text = note?.text ?? '';
      // 目标切换（含编辑器收起）都回备注态：名册态是单次编辑内的换装，
      // 不跨目标残留。
      _rosterMode = false;
      _dancerController.clear();
      _dancerHint = null;
    }
    if (target != null && note == null) {
      // 目标备注消失即清编辑目标：编辑器内「删除」与贴纸左上角
      // 删除两处入口同经 [AnnotationEditor.removeNote]，目标清理由面板按
      // 「目标备注消失」这一处统一收口——删完面板收起、不留指向已失效
      // 备注的目标；随后撤销把那条备注恢复回来时也不会再弹出一个带着旧
      // 文本的编辑框（目标已空，恢复不重新打开）。post-frame 清，不在
      // 构建中改 provider。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(noteTextEditorTargetProvider) == target) {
          ref.read(noteTextEditorTargetProvider.notifier).close();
        }
      });
    }
    if (target == null || note == null) return const SizedBox.shrink();
    // 名册短暂提示的触达面：编辑器打开即记一次触达（autofocus
    // 随之升起键盘；幂等，是否演出由状态位裁决）。
    return GuideBadgeTrigger(
      unitId: badgeRosterUnitId,
      child: PopScope(
        // 出口③：系统返回键 = 收起即存、不退出播放页
        // ——否则刚打的字随页面 pop 一并丢失。编辑面收起后本层整体消失，
        // 返回键行为回到播放页原样。
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _collapse();
        },
        // 键盘感知取数走共用件（坑注释见其文档）。
        child: WindowMetricsWatcher(
          builder: (context, viewData) {
            // 停靠位 = 当前窗口键盘下沿，逐帧跟随：键盘升起是逐帧到达的 inset
            // 动画（真机实测 0 → 18.3 → … → 255.1 逻辑像素），跟随当前值才能
            // 落在最终键盘上沿之上；键盘变高变矮、收起回底部都跟着走。
            final dockedInset = viewData.viewInsets.bottom;
            // 底距 = max(键盘内缩, 系统手势内缩)：键盘收起时
            // 输入条不压在系统手势条上；键盘升起时键盘内缩恒为较大者。
            final dockPadding = math.max(
              dockedInset,
              viewData.systemGestureInsets.bottom,
            );
            final docked = dockedInset > 0;
            final safeHeight = viewData.size.height - dockedInset;
            _scheduleShrinkCheck(docked, safeHeight);
            // 停靠内容 = 输入条本体：停靠时用 OverflowBox 让它按自然尺寸量测
            // （不被键盘上方的矮约束钳成溢出异常），再由 [_maybeScale] 把超高
            // 的部分缩回安全带内。
            final content = _maybeScale(_buildBar(index, viewData.orientation));
            return GestureDetector(
              // 出口②：点输入条以外任意处收起即存。不透明铺满，
              // 输入条自身的点击由条内手势吸收、不落进这里。
              behavior: HitTestBehavior.opaque,
              onTap: _collapse,
              child: Padding(
                // 停靠 = 整条位移：形态不变，只是把这一行抬到键盘上沿之上。
                padding: EdgeInsets.only(bottom: dockPadding),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: docked
                      ? OverflowBox(
                          alignment: Alignment.bottomCenter,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: content,
                        )
                      : content,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 输入条本体（位移与缩小都在这一层之外——形态不变、只是位移与缩放）。
  /// 横屏**一条横排**；竖屏改**两行**：上行输入框满宽，下行动作区
  /// 一排（舞者快捷区、名册、删除、完成）——361dp 宽下横排会把输入框挤到
  /// 零宽，两行让输入框与动作区各得其所。
  ///
  /// 名册态**原地换装**：左段在备注输入框与舞者输入框（+「新建」）
  /// 之间切换、同一枚钮在「名册 / 返回备注编辑」之间变文案；舞者快捷区与
  /// 左段同行（横屏）/ 同处下行动作区（竖屏），长文本在框内滚动、词条段横
  /// 滚，都不撑破所在行。
  Widget _buildBar(int index, Orientation orientation) => GestureDetector(
    key: _dockContentKey,
    // 输入条内的点击不外泄给「点外收起」（空隙处点按不算点外）。
    onTap: () {},
    child: Container(
      key: const Key('note_text_editor'),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kNoteEditorPanelColor,
        borderRadius: BorderRadius.circular(kNoteEditorPanelRadius),
      ),
      child: orientation == Orientation.portrait
          ? _buildPortraitRows(index)
          : _buildLandscapeRow(index),
    ),
  );

  /// 横屏那一条横排（形态逐位不变）。
  Widget _buildLandscapeRow(int index) => Row(
    children: [
      ..._inputChildren(),
      DancerRosterChipBar(
        rosterMode: _rosterMode,
        onInsertDancer: _insertDancerMention,
      ),
      _rosterToggleButton(),
      _deleteButton(index),
      _doneButton(),
    ],
  );

  /// 竖屏两行：上行输入框满宽（名册态时右缀「新建」），下行动作
  /// 区一排——舞者快捷区占满剩余宽（[Expanded]），随后是名册 / 删除 / 完成。
  Widget _buildPortraitRows(int index) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: _inputChildren()),
      Row(
        children: [
          Expanded(
            child: DancerRosterChipBar(
              rosterMode: _rosterMode,
              onInsertDancer: _insertDancerMention,
            ),
          ),
          _rosterToggleButton(),
          _deleteButton(index),
          _doneButton(),
        ],
      ),
    ],
  );

  /// 输入段（横竖屏共用）：输入框吃满可用宽，名册态时右缀「新建」。
  List<Widget> _inputChildren() => [
    Expanded(child: _rosterMode ? _buildDancerField() : _buildNoteField()),
    if (_rosterMode)
      _toolbarTextButton(
        key: const Key('note_editor_roster_new'),
        label: '新建',
        color: Colors.white70,
        onPressed: _createDancer,
      ),
  ];

  /// 「名册 / 返回备注编辑」原地换装钮（横竖屏共用）：包名册短暂提示的
  /// 锚点包装器，被包钮的行为与外观逐位不变。
  Widget _rosterToggleButton() => GuideAnchor(
    anchorKey: rosterButtonAnchorKey,
    child: _toolbarTextButton(
      key: const Key('note_editor_roster'),
      label: _rosterMode ? '返回备注编辑' : '名册',
      color: Colors.white70,
      onPressed: () => setState(() => _rosterMode = !_rosterMode),
    ),
  );

  Widget _deleteButton(int index) => _toolbarTextButton(
    key: const Key('note_editor_delete'),
    label: '删除',
    color: Colors.white70,
    onPressed: () =>
        ref.read(annotationEditorProvider).submit(RemoveNote(index: index)),
  );

  Widget _doneButton() => _toolbarTextButton(
    key: const Key('note_editor_done'),
    label: '完成',
    color: Colors.white,
    onPressed: _collapse,
  );

  /// 备注输入框（备注态左段，形态不变）。
  Widget _buildNoteField() => TextField(
    key: const Key('note_text_editor_field'),
    controller: _controller,
    autofocus: true,
    // 单行标签：输入框单行、回车不产生换行、粘贴进来的换行
    // 当场归一为空格。
    maxLines: 1,
    inputFormatters: const [NoteSingleLineFormatter()],
    style: const TextStyle(color: Colors.white, fontSize: 16),
    decoration: const InputDecoration(
      isDense: true,
      hintText: '输入备注…',
      hintStyle: TextStyle(color: kNoteFieldHintColor),
      border: InputBorder.none,
    ),
  );

  /// 舞者输入框（名册态左段）：回车与「新建」同一条新建路径。
  /// 下方内联提示位：空白名提交时在此说明为什么没建，输入变化
  /// 即清。
  Widget _buildDancerField() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Flexible(
        child: TextField(
          key: const Key('note_editor_dancer_field'),
          controller: _dancerController,
          focusNode: _dancerFocus,
          autofocus: true,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _createDancer(),
          onChanged: (_) => _clearDancerHint(),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: const InputDecoration(
            isDense: true,
            hintText: '输入舞者名…',
            hintStyle: TextStyle(color: kNoteFieldHintColor),
            border: InputBorder.none,
          ),
        ),
      ),
      if (_dancerHint != null)
        Text(
          key: const Key('note_editor_dancer_hint'),
          _dancerHint!,
          style: const TextStyle(color: kNoteFieldHintColor, fontSize: 12),
        ),
    ],
  );

  /// 新建舞者（回车与「新建」同路）：只建人、不自动把
  /// 点名写进备注（名册态左段已不是备注框，结构上就写不进去）；建完
  /// 立刻弹 24 色选色浮层——那期间键盘收起（先撤焦点再弹浮层）；浮层
  /// 关闭后焦点交回舞者输入框，可连续输入下一个名字。空白名不再静默忽略
  /// 给一句内联提示说明为什么没建，输入
  /// 变化即清。
  Future<void> _createDancer() async {
    final name = _dancerController.text.trim();
    if (name.isEmpty) {
      setState(() => _dancerHint = '名字是空的，所以没建——请先输入舞者名');
      return;
    }
    if (_dancerHint != null) _clearDancerHint();
    _dancerController.clear();
    _dancerFocus.unfocus();
    final roster = ref.read(dancerRosterControllerProvider);
    await roster.addDancer(
      name,
      color: firstUnusedPaletteColor(roster.roster.map((entry) => entry.color)),
    );
    if (!mounted) return;
    await showDancerColorPicker(context, ref, name);
    if (!mounted || !_rosterMode) return;
    _dancerFocus.requestFocus();
  }

  /// 呈现层临时缩小判定（帧后量测）：停靠内容高于键盘
  /// 上方安全空间时按比例缩小到放得下；放得下 / 退出编辑恢复原尺寸。只在
  /// 呈现层、不触碰任何持久化状态。回调带 pending 守卫：同帧多次构建只排
  /// 一次，量测后无变化不重建、不空转。
  void _scheduleShrinkCheck(bool docked, double safeHeight) {
    if (_shrinkCheckPending) return;
    if (!docked) {
      if (_shrinkScale != null) {
        _shrinkCheckPending = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _shrinkCheckPending = false;
          if (mounted) setState(() => _shrinkScale = null);
        });
      }
      return;
    }
    _shrinkCheckPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shrinkCheckPending = false;
      if (!mounted) return;
      final box =
          _dockContentKey.currentContext?.findRenderObject() as RenderBox?;
      final height = box?.size.height;
      if (height == null || height <= 0) return;
      final overshoot = height > safeHeight;
      final next = overshoot ? safeHeight / height : null;
      if (next != _shrinkScale) {
        setState(() => _shrinkScale = next);
      }
    });
  }

  /// 缩小包裹形（底中对齐）：只在呈现层缩，形态不变。
  Widget _maybeScale(Widget child) => _shrinkScale == null
      ? child
      : Transform.scale(
          scale: _shrinkScale,
          alignment: Alignment.bottomCenter,
          child: child,
        );

  /// 带文字的工具钮（工具全部带文字，不靠图标猜）。命中盒
  /// 下限抬到通行 48——文字钮本无可见底色，
  /// 命中矩形外扩不改任何视觉（文字 14 档、横向内边距 8 原样）；横竖屏
  /// 停靠条上各钮独占盒子、互不重叠，48 达得到、不走密集区兜底。
  Widget _toolbarTextButton({
    required Key key,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) => TextButton(
    key: key,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(kHitTargetMinSize, kHitTargetMinSize),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: onPressed,
    child: Text(label, style: TextStyle(color: color, fontSize: 14)),
  );
}
