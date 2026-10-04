import '../persistence/song_signature.dart';
import 'song_naming_contract.dart';
import '../stats/song_signature.dart';

/// 命名对话框的呈现接缝：域把初值、回退文本与是否可点框外收起
/// 交给宿主，宿主（widget 层）负责按构建上下文弹出命名框并交回用户结论。
/// 返回值 null = 页面已卸载或点框外收起，域按「不提交」处理。
typedef SongNamingPresenter = Future<SongNamingResult?> Function({
  required SongNamingInitial initial,
  required String fallbackFileName,
  required bool barrierDismissible,
});

/// 歌曲署名的命名会话域：自持首次导入判定、命名/改名编排与
/// 提交路径，宿主不再持有这些方法。
///
/// **接线形状（本仓第一个带对话框的域，供后续需要构建上下文的域照抄）**：
/// **域出编排与提交、页面出对话框**。域不读构建上下文、不 import 容器中枢；
/// 需要弹窗时经注入的 [SongNamingPresenter] 把场景初值交给宿主，宿主弹完
/// 把用户结论交回域，域只接收结果并决定跳过/保存的语义与后续写盘。
///
/// **依赖方向（单向，护栏钉住）**：命名域 → 署名域（[SongSignatureController]
/// 是署名读写的唯一执行端）。署名域的提交通知由统计域自持订阅（统计域 →
/// 署名域是另一条既有单向边）；命名域与统计域之间无直接调用，也
/// 不经宿主回调绕行——跨域写-through 由署名域自己的提交信号发出。
///
/// - [promptImportIfNeeded]：首次导入编排。已署名或非新导入直接返回；
///   否则弹 import 场景命名框（不可点框外收起），保存提交输入现值、
///   跳过按文件名署名（之后不再弹——署名已落盘）。
/// - [rename]：顶栏改名编排。弹 rename 场景命名框（带出现值、可点框外
///   收起），保存提交、取消不改名。
/// - [titleText]：顶栏署名显示串（未署名回退文件名）。
class SongNamingSession {
  SongNamingSession({
    required this._signatureController,
    required this._fallbackFileName,
    required this._presentNaming,
  });

  final SongSignatureController _signatureController;

  /// 未署名时的回退文件名（与顶栏回退一致）。
  final String Function() _fallbackFileName;

  final SongNamingPresenter _presentNaming;

  /// 顶栏标题显示串：署名为空部分省略，未署名回退文件名。
  String get titleText =>
      signatureDisplayText(_signatureController.signature, _fallbackFileName());

  /// 首次导入编排（[isNewImport] = 本次打开是否来自首次导入）：解析后已署名
  /// 或非新导入时不弹；否则弹命名框并在关闭后按结论提交。调用点在镜像 resolve
  /// 之前（装载表声明次序：署名解析（含命名框） → 镜像 resolve），命名框关闭
  /// 即镜像询问开始，两个模态不叠置。
  Future<void> promptImportIfNeeded({required bool isNewImport}) async {
    if (!isNewImport || _signatureController.signature != null) return;
    await _presentAndCommit(SongNamingScene.import);
  }

  /// 顶栏署名编辑入口：打开同款 `rename` 场景（三字段带出现值、
  /// 实时预览），保存提交署名、取消（含点框外）= 不改名。
  Future<void> rename() => _presentAndCommit(SongNamingScene.rename);

  /// 场景决定对话框与结论语义：导入命名不可点框外收起、跳过 = 按文件名
  /// 署名（之后不再弹）；改名可点框外收起、跳过/取消 = 不改名。
  Future<void> _presentAndCommit(SongNamingScene scene) async {
    final fallback = _fallbackFileName();
    final isImport = scene == SongNamingScene.import;
    final result = await _presentNaming(
      initial: resolveSongNamingInitial(
        scene: scene,
        current: _signatureController.signature,
        fallbackFileName: fallback,
      ),
      fallbackFileName: fallback,
      barrierDismissible: !isImport,
    );
    if (result == null) return;
    if (!result.confirmed) {
      if (!isImport) return;
      await _commit(SongSignature(song: fallback), fallback);
      return;
    }
    await _commit(result.signature, fallback);
  }

  /// 提交路径（导入命名 / 改名共用）：控制器净化后双写 index + markers
  /// （内存态即时生效 → 标题刷新）；随后署名域自己发出提交通知，统计域
  /// 据此把署名快照写-through 迁移。
  Future<void> _commit(SongSignature raw, String fallbackSong) async {
    await _signatureController.applySignature(raw, fallbackSong: fallbackSong);
  }
}
