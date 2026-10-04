import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../persistence/song_signature.dart';
import 'song_naming_contract.dart';
import 'window_keyboard_metrics.dart';

export 'song_naming_contract.dart';

/// 歌曲署名命名/改名对话框。
///
/// 三字段编辑：版本舞者（可填）、歌曲名（必填且初值由宿主给出——导入
/// 为空、改名现歌名）、版本注记（可填），表单首行实时预览显示串。「保存」
/// 在歌曲名 trim 非空时可用，经 [Navigator.pop] 返回 [SongNamingResult]
/// （[confirmed] = true）。
///
/// 退路钮与标题随**场景**（必填参数 [scene]）：导入命名标题「命名」、退路钮
/// 「跳过（按文件名命名）」+ `naming_skip`（返回 [SongNamingResult]
/// [confirmed] = false，由宿主按文件名回落名署名）；改名标题「重命名」、
/// 退路钮「取消」+ `naming_cancel`（[confirmed] = false，由宿主按不改处理）。
class SongNamingDialog extends StatefulWidget {
  const SongNamingDialog({
    super.key,
    required this.scene,
    required this.initialSong,
    this.initialDancer = '',
    this.initialRemark = '',
    this.fallbackText = '',
  });

  /// 命名场景：导入命名 / 改名。退路钮的文案与测试键、标题都由它决定——
  /// 对话框不靠别的字段反推。
  final SongNamingScene scene;

  /// 歌曲名初值（导入命名 = 空；改名 = 现歌名）。
  final String initialSong;

  /// 预览回退文本（文件名回落名）：歌曲名为空时预览与保存后的实际落盘值
  /// （回退文件名回落名）保持一致。
  final String fallbackText;

  /// 版本舞者初值（改名带出现值）。
  final String initialDancer;

  /// 版本注记初值（改名带出现值）。
  final String initialRemark;

  @override
  State<SongNamingDialog> createState() => _SongNamingDialogState();
}

/// 横屏浮层单行可编辑的字段（以物理方向 + 键盘状态切形态）。
enum _NamingField { dancer, song, remark }

class _SongNamingDialogState extends State<SongNamingDialog> {
  late final TextEditingController _dancer;
  late final TextEditingController _song;
  late final TextEditingController _remark;
  late final FocusNode _songFocus;
  late final FocusNode _dancerFocus;
  late final FocusNode _remarkFocus;
  _NamingField _overlayField = _NamingField.song;
  // 每字段一个稳定 GlobalKey：浮层与完整表单之间切换时，正在编辑的字段
  // 从 ListBody 换到 Row（换父级）。ValueKey 无法跨父级重挂载，字段会被
  // 销毁重建 → EditableText 关闭 TextInputConnection → 真机系统键盘收回。
  // GlobalKey 让该字段整棵子树被重挂载，State（含输入连接）沿用，
  // 键盘保持弹起。
  final GlobalKey _songKey = GlobalKey();
  final GlobalKey _dancerKey = GlobalKey();
  final GlobalKey _remarkKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _dancer = TextEditingController(text: widget.initialDancer);
    _song = TextEditingController(text: widget.initialSong);
    _remark = TextEditingController(text: widget.initialRemark);
    _songFocus = FocusNode();
    _dancerFocus = FocusNode();
    _remarkFocus = FocusNode();
    _dancerFocus.addListener(() => _onFocus(_NamingField.dancer));
    _remarkFocus.addListener(() => _onFocus(_NamingField.remark));
    _songFocus.addListener(() => _onFocus(_NamingField.song));
    _songFocus.addListener(_placeCaretAtSongEnd);
  }

  /// 打开即落定光标：首次获得焦点时把选区折到文本末尾（改名"接着改"
  /// 的落点），随即摘掉监听——此后手动切字段不再动光标。
  void _placeCaretAtSongEnd() {
    if (!_songFocus.hasFocus) return;
    _songFocus.removeListener(_placeCaretAtSongEnd);
    final offset = _song.text.length;
    _song.selection = TextSelection.collapsed(offset: offset);
  }

  void _onFocus(_NamingField field) {
    if (_fieldMeta(field).focus.hasFocus && _overlayField != field) {
      setState(() => _overlayField = field);
    }
  }

  /// 横屏浮层内切字段：请求焦点（键盘保持弹起）、更新当前编辑字段。
  void _switchOverlayField(_NamingField field) {
    setState(() => _overlayField = field);
    _fieldMeta(field).focus.requestFocus();
  }

  @override
  void dispose() {
    _dancer.dispose();
    _song.dispose();
    _remark.dispose();
    _songFocus.dispose();
    _dancerFocus.dispose();
    _remarkFocus.dispose();
    super.dispose();
  }

  /// 实时预览的署名（随输入即时更新）。
  SongSignature get _draft => SongSignature(
    dancer: _dancer.text,
    song: _song.text,
    remark: _remark.text,
  );

  /// 「保存」可用性 = 歌曲名 trim 非空；净化层
  /// 的「歌曲名空 → 回退文件名」仍是防御契约，UI 门不替代它。
  bool get _canSave => _song.text.trim().isNotEmpty;

  void _pop(bool confirmed) =>
      Navigator.of(context)
          .pop(SongNamingResult(confirmed: confirmed, signature: _draft));

  /// 退路钮（顶部栏专用；浮层内不出现）：返回 confirmed:false，由宿主按场景
  /// 收口语义（导入 = 按文件名回落名署名 / 改名 = 取消，什么都不改）。
  /// 文案与测试键都由场景决定——钮上说出按下去会发生什么。
  Widget _fallbackButton() {
    final isImport = widget.scene == SongNamingScene.import;
    return TextButton(
      key: Key(isImport ? 'naming_skip' : 'naming_cancel'),
      onPressed: () => _pop(false),
      child: Text(isImport ? '跳过（按文件名命名）' : '取消'),
    );
  }

  /// 顶部栏标题：导入命名「命名」（这支舞还没有名字可「重」）、改名「重命名」。
  String get _title => widget.scene == SongNamingScene.import ? '命名' : '重命名';

  /// 「保存」动作（顶部栏与浮层共用）：歌名 trim 非空才可用。
  Widget _saveButton() => FilledButton(
    key: const Key('naming_save'),
    onPressed: _canSave ? () => _pop(true) : null,
    child: const Text('保存'),
  );

  /// 字段元数据单一来源：controller/focus/表单 label/浮层短 label/测试
  /// key/初始焦点/选填灰字标注（浮层短 label 用「舞者名/注记」缩写，避免与
  /// 备注贴纸体系的「备注」撞名）。
  ({
    TextEditingController controller,
    FocusNode focus,
    String label,
    String overlayLabel,
    Key key,
    GlobalKey globalKey,
    bool autofocus,
    bool optional,
  })
  _fieldMeta(_NamingField field) => switch (field) {
    _NamingField.dancer => (
      controller: _dancer,
      focus: _dancerFocus,
      label: '舞者名',
      overlayLabel: '舞者名',
      key: const Key('naming_dancer_field'),
      globalKey: _dancerKey,
      autofocus: field == _NamingField.song,
      optional: true,
    ),
    _NamingField.song => (
      controller: _song,
      focus: _songFocus,
      label: '歌曲名',
      overlayLabel: '歌曲名',
      key: const Key('naming_song_field'),
      globalKey: _songKey,
      // 打开即聚焦歌曲名：进去就能改歌名，键盘随之弹起。
      autofocus: field == _NamingField.song,
      optional: false,
    ),
    _NamingField.remark => (
      controller: _remark,
      focus: _remarkFocus,
      label: '备注',
      overlayLabel: '注记',
      key: const Key('naming_remark_field'),
      globalKey: _remarkKey,
      autofocus: field == _NamingField.song,
      optional: true,
    ),
  };

  Widget _textField(_NamingField field) {
    final meta = _fieldMeta(field);
    final colorScheme = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: meta.globalKey,
      child: TextField(
        key: meta.key,
        controller: meta.controller,
        focusNode: meta.focus,
        autofocus: meta.autofocus,
        decoration: InputDecoration(
          label: meta.optional
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(meta.label),
                    const SizedBox(width: 6),
                    Text(
                      '可选',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              : Text(meta.label),
        ),
        inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  /// 横屏浮层内切换钮指向的字段：歌曲名 ↔ 舞者名往返，当前字段为备注时
  /// 指向歌曲名（备注在浮层内不可达，需先收起键盘）。
  _NamingField get _overlaySwitchTarget => _overlayField == _NamingField.song
      ? _NamingField.dancer
      : _NamingField.song;

  /// 横屏键盘弹起的浮层单行：字段名｜输入｜「输入X」切字段钮｜保存
  /// 浮层内不出现退路钮（导入/改名都一样）。
  Widget _buildOverlayRow() {
    final target = _overlaySwitchTarget;
    return Padding(
      key: const Key('naming_overlay_row'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            _fieldMeta(_overlayField).overlayLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(width: 8),
          Expanded(child: _textField(_overlayField)),
          TextButton(
            key: Key('naming_switch_${target.name}'),
            onPressed: () => _switchOverlayField(target),
            child: Text('输入${_fieldMeta(target).overlayLabel}'),
          ),
          _saveButton(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 键盘抬升取数走共用件（坑注释见其文档）。抬升经
    // TweenAnimationBuilder 过渡，且浮层/表单形态用同一动画值判定：过渡帧里
    // 形态与剩余空间一致，不会把完整表单塞进仍被抬升占据的空间而溢出。
    return WindowMetricsWatcher(
      builder: (context, viewData) {
        // 以物理方向判定（横屏锁定/竖屏），不用剩余高度阈值（避免方向锁定时跳动）。
        final isLandscape = viewData.size.width > viewData.size.height;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: viewData.viewInsets.bottom),
          duration: const Duration(milliseconds: 200),
          builder: (context, bottomInset, _) {
            final overlay = isLandscape && bottomInset > 0;
            return Padding(
              key: const Key('song_naming_keyboard_inset'),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Material(
                    key: const Key('song_naming_dialog'),
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    elevation: 6,
                    child: SafeArea(
                      child: overlay
                          ? _buildOverlayRow()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 顶部栏：退路钮/保存与标题同一行。竖屏单侧空间
                                // 不足分居两端（左退路右保存）；横屏两动作并排
                                // 聚在右上角。
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    8,
                                    8,
                                    0,
                                  ),
                                  child: Row(
                                    children: isLandscape
                                        ? [
                                            Expanded(
                                              child: Text(
                                                _title,
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                            ),
                                            _fallbackButton(),
                                            _saveButton(),
                                          ]
                                        : [
                                            _fallbackButton(),
                                            Expanded(
                                              child: Text(
                                                _title,
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                            ),
                                            _saveButton(),
                                          ],
                                  ),
                                ),
                                const Divider(height: 16),
                                // 内容区：完整表单（键盘弹起时缩到键盘上方、字段区内滚动）。
                                Flexible(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      0,
                                      24,
                                      24,
                                    ),
                                    child: ListBody(
                                      children: [
                                        ListenableBuilder(
                                          listenable: Listenable.merge([
                                            _dancer,
                                            _song,
                                            _remark,
                                          ]),
                                          builder: (context, _) => Text(
                                            signatureDisplayText(
                                              _draft,
                                              widget.fallbackText,
                                            ),
                                            key: const Key('naming_preview'),
                                            // 浅色卡上的正文：黑底胶囊的白字在这里读不出来。
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _textField(_NamingField.dancer),
                                        _textField(_NamingField.song),
                                        _textField(_NamingField.remark),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
