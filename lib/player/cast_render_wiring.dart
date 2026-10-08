/// 投屏渲染请求的装配（播放页侧）：把各域读面读成一份
/// [CastRenderRequest]——**设置快照、标注指纹与拍声排程在这里各就各位**。
///
/// 播放页是组合根，也是唯一同时看得见镜像、取景、节拍呈现、音源段表与音量
/// 口径的地方；投屏域看不到它们（依赖方向护栏）。于是「读它们 → 折成一份
/// 请求」这一步住在这里，投屏域只吃值对象。
///
/// 一次请求读的是**当下**的取值：请求是给这一次渲染用的快照，用户在面板里改
/// 勾选就重新装配一份（勾选档是请求的一部分）。
library;

import 'package:flutter/painting.dart' show Rect, Size, TextScaler;
import 'package:riverpod/misc.dart' show ProviderListenable;

import '../annotation/framing_selection.dart' show FramingSelection;
import '../annotation/note_sticker.dart' show NoteSticker;
import '../beat_track_state/beat_track_state.dart'
    show beatGridProvider, beatTrackStateProvider;
import '../cast/cast_annotation_fingerprint.dart';
import '../cast/cast_beat_count.dart';
import '../cast/cast_encoder_realtime.dart' show CastRenderResolution;
import '../cast/cast_range_gate.dart' show CastRange;
import '../cast/cast_render_request.dart';
import '../core/current_beat.dart' show BeatCountDisplay;
import 'annotation_editor.dart'
    show
        annotationTimelineProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'beat_animation.dart' show beatAnimationStyleProvider;
import 'beat_count_layout.dart'
    show beatNumbersCanvasSize, beatNumbersScaleInContent;
import 'beat_presentation.dart'
    show
        BeatPresentationFacts,
        assembleBeatPresentationContext,
        evaluatePresentationValue;
import 'beat_presentation_providers.dart'
    show beatOverlayContentVisibleProvider, beatPresentationFactsProvider;
import 'cast_beat_clicks.dart' show buildCastBeatClicks;
import 'cast_beat_placement.dart'
    show
        CastBeatPlacement,
        castBeatContentRect,
        castBeatPlacementInPicture;
import 'cast_beat_sheet.dart'
    show castBeatNumbersSizeOf, renderCastBeatSheet;
import 'cast_sticker_sheet.dart'
    show castStickerSheetLogicalSize, renderCastStickerSheet;
import 'dancer_roster_controller.dart' show dancerRosterProvider;
import 'framing_session_state.dart' show framingStateProvider;
import 'metronome_overlay.dart' show beatCountTextOf;
import 'metronome_sound.dart' show metronomeHalfBeatEnabledProvider;
import 'metronome_source_registry.dart'
    show effectiveMetronomeSourceIdProvider, metronomeSourceEntryOfId;
import 'note_sticker_overlay.dart' show noteMentionRosterColors;
import 'overlay.dart' show OverlayPlacementCell, OverlayPlacements;
import 'song_loudness.dart'
    show
        metronomePlayVolumeProvider,
        metronomeVolumeProvider,
        songLoudnessBaselineProvider;

/// 读一个 provider 的取值：`Ref.read` 与 `WidgetRef.read` 是同一签名
/// （Riverpod 没有二者的共同超类型），接线处传 `ref.read` 即可——组合根
/// （播放页，WidgetRef）与测试（ProviderContainer 的 Ref）共用同一份装配。
typedef CastRenderRead = T Function<T>(ProviderListenable<T> provider);

/// 取景选区的规范串（空 = 未取景 = 整帧）：进设置快照，四位小数足够区分用户
/// 圈得出来的任何选区。
String castFramingToken(FramingSelection? selection) {
  if (selection == null) return '';
  return [
    selection.left,
    selection.top,
    selection.right,
    selection.bottom,
  ].map((value) => value.toStringAsFixed(4)).join(',');
}

/// 一条备注贴纸 → 一份**第二路输入**（`#29`）：带 alpha 的单帧 PNG 的字节口 +
/// 时间窗 + 归一化落位与尺寸分数。
///
/// **尺寸分数**是「贴纸可见墨迹的逻辑尺寸 ÷ **上屏画面矩形**」——两个量都在
/// 这一处从同一份材料算出来（[castStickerSheetLogicalSize] 与调用方给的画面矩形
/// 尺寸），因此电视上的贴纸与手机上的贴纸占同一块画面的同一个比例，与源分辨率、
/// 投屏倍速档都无关。
///
/// 画面矩形量不到（空尺寸 / 宽高比未知）时给空表：宁可不装这一条第二路输入，
/// 也不拿一个错的比例去烤一份副本（与「探测不到一律按不显示处理」同口径）。
List<CastSticker> buildCastStickers({
  required List<NoteSticker> notes,
  required Map<String, int> rosterColors,
  required Size pictureSize,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (notes.isEmpty || pictureSize.isEmpty) return const [];
  if (!pictureSize.width.isFinite ||
      !pictureSize.height.isFinite ||
      pictureSize.width <= 0 ||
      pictureSize.height <= 0) {
    return const [];
  }
  final sheets = <CastSticker>[];
  for (final note in notes) {
    if (note.endMs <= note.startMs) continue;
    final scale = note.geometry.scale;
    if (!scale.isFinite || scale <= 0) continue;
    final logical = castStickerSheetLogicalSize(
      note: note,
      rosterColors: rosterColors,
      textScaler: textScaler,
    );
    // 空文本之类量不出墨迹的备注：没有可画的字，就不装这一条输入。
    if (logical == null) continue;
    sheets.add(
      CastSticker(
        // 惰性取字节：装配是同步的，画字留到渲染编排写文件那一刻。
        imageBytesOf: () async {
          final raster = await renderCastStickerSheet(
            note: note,
            rosterColors: rosterColors,
            textScaler: textScaler,
          );
          if (raster == null) {
            // 量得出墨迹却画不出来：宁可这次渲染失败，也不推一份缺字的副本。
            throw StateError('贴纸图画不出来（${note.startMs}ms 起那条备注）');
          }
          return raster.bytes;
        },
        startMs: note.startMs,
        endMs: note.endMs,
        centerX: note.geometry.centerX,
        centerY: note.geometry.centerY,
        widthFraction: logical.width / pictureSize.width,
        heightFraction: logical.height / pictureSize.height,
      ),
    );
  }
  return sheets;
}

/// 贴纸**尺寸分量**的记号（进缓存键的设置快照；空 = 这次不装贴纸）。
///
/// 逐条取 [CastSticker.sizeToken]（次序即请求里的贴纸次序）——两个尺寸分数是
/// 上面从「墨迹逻辑尺寸 ÷ 上屏画面矩形」现算的，**不在标注指纹里**（指纹收的
/// 是文档里那份几何与尺寸系数），于是系统字号缩放与画面矩形（转屏）都会改
/// 产物却没有痕迹。这一条记号把它们收进键，与数拍层的 `beatOverlay` 同款。
String castStickerOverlayToken(List<CastSticker> stickers) => [
  for (final sticker in stickers) sticker.sizeToken,
].join('|');

/// **逐拍静态数字的时间窗**（`#30`）：源时间轴上连续覆盖 `[0, duration]` 的一串
/// 半开窗，每格带那一刻该画的文字（null = 这一段不显示数拍）。
///
/// ## 取值与手机同一处求值
///
/// 逐拍走节拍呈现的同一条链：素材面 → [assembleBeatPresentationContext] →
/// [evaluatePresentationValue]（与上屏浮层读的是同一次求值），文字经
/// [beatCountTextOf] 折成字符串。数字因此**冻结在渲染那一刻**：这里算出来的
/// 就是烤进副本的那几个字；投屏期间手机上重新锚定学习段，副本里那份不会跟着
/// 变（ADR-0004 已记录的偏差）。
///
/// ## 分界点（一格之内取值不变的依据）
///
/// 数拍数字在一拍之内不变，但会在四处跳变：**拍点**、**分段线**（锚点链取
/// 位置之前最近的那条线）、**首线**与**会话锚**（录制锚 / 延迟锚 / 激活段段首，
/// 它们各自从出现的位置起改锚）。故分界点 = `{0, 显示域终点, 总时长}` ∪ 显示域
/// 内的每个拍点 ∪ 上述四处。每一格在自己的左端点求一次值——一格之内因此取值
/// 恒定（这一条由 `test/player/cast_render_wiring_test.dart` 的逐点比对钉住）。
///
/// ## 显示域的终点是**末拍起点**（与手机逐位一致）
///
/// 手机上的数拍在「位置晚于末拍」时无拍可数（`_resolveBeatAnchor` 的
/// `position > gridLastBeatTime → null`），故显示域是 `[0, 末拍起点]`：末拍之后
/// 的那一段是**不显示**的格，不是把最后一个号一直挂着。无界网格（占位/异常
/// 均匀实现）没有终点，取整片。
List<CastBeatCountRow> castBeatRowsOf({
  required BeatPresentationFacts facts,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return const [];
  final context = assembleBeatPresentationContext(
    facts,
    rate: 1,
    playing: false,
  );
  if (context.gridError) return const [];
  final grid = context.grid;
  final totalMs = duration.inMilliseconds;
  final lastIndex = grid.lastBeatIndex;
  final displayEndMs = lastIndex == null
      ? totalMs
      : grid.beatTime(lastIndex).inMilliseconds.clamp(0, totalMs);

  final cuts = <int>{0, displayEndMs, totalMs};
  void addCut(Duration? at) {
    if (at == null) return;
    final ms = at.inMilliseconds;
    if (ms > 0 && ms < displayEndMs) cuts.add(ms);
  }

  for (final beat in grid.beatsInWindow(
    Duration.zero,
    Duration(milliseconds: displayEndMs),
  )) {
    addCut(beat);
  }
  addCut(context.firstLine);
  for (final line in context.segmentLines) {
    addCut(line);
  }
  addCut(context.recordingAnchor);
  addCut(context.delayAnchor);
  addCut(context.activeAnchor);

  final points = cuts.toList()..sort();
  final rows = <CastBeatCountRow>[];
  for (var i = 0; i + 1 < points.length; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (end <= start) continue;
    // 显示域之外（末拍之后那一段）：不显示——与手机上「无拍可数」同判。
    final text = start >= displayEndMs
        ? null
        : () {
            final value = evaluatePresentationValue(
              context: context,
              position: Duration(milliseconds: start),
            );
            return value == null ? null : castBeatTextOf(value.display);
          }();
    final previous = rows.isEmpty ? null : rows.last;
    if (previous != null && previous.text == text) {
      rows[rows.length - 1] = CastBeatCountRow(
        startMs: previous.startMs,
        endMs: end,
        text: text,
      );
      continue;
    }
    rows.add(CastBeatCountRow(startMs: start, endMs: end, text: text));
  }
  return rows;
}

/// 数拍数字的文字取值 → 投屏域的值对象（两处只差一个包装：取值本身仍由
/// `metronome_overlay.dart` 的 [beatCountTextOf] 一处派生）。
CastBeatCountText castBeatTextOf(BeatCountDisplay display) {
  final text = beatCountTextOf(display);
  return CastBeatCountText(
    eightCount: text.eightCount,
    group: text.group,
    beatCount: text.beatCount,
  );
}

/// 装配数拍层（`#30`）：不装时给 null。
///
/// 装的条件逐条与手机对齐：勾了**画面类**（数拍属于画面内容类）、**数拍显示**
/// 开着、网格不是异常态、**落位量得出来**（四格浮层位 + 当前视口 + 画面矩形
/// 齐全）、且至少有一格真的要画数字。任一条不成立就不装——宁可不画也不画错。
///
/// 画布：全部行里**最大**的那一份数字行 → 固定底衬尺寸（图像序列是单条流，
/// 各格像素尺寸必须一致）；每格把底衬居中画进去，而底衬中心正是手机上那一行
/// 数字的中心（落位由 [castBeatPlacementInPicture] 换算）。
({CastBeatPlacement placement, CastBeatCountOverlay overlay})?
buildCastBeatOverlay({
  required CastRenderRead read,
  required Duration duration,
  required CastRenderChoices choices,
  required Rect? pictureRect,
  required TextScaler textScaler,
  required OverlayPlacements? placements,
  required OverlayPlacementCell cell,
  required Size? viewport,
}) {
  if (!choices.picture) return null;
  if (!read(beatOverlayContentVisibleProvider)) return null;
  final picture = pictureRect;
  if (picture == null || placements == null || viewport == null) return null;
  final rows = castBeatRowsOf(
    facts: read(beatPresentationFactsProvider),
    duration: duration,
  );
  if (!rows.any((row) => row.visible)) return null;

  final style = read(beatAnimationStyleProvider);
  final textScale = textScaler.scale(1);
  final numbersSize = castBeatNumbersSizeOf(
    rows: rows,
    textScaler: textScaler,
  );
  if (numbersSize == null) return null;
  final placement = castBeatPlacementInPicture(
    placements: placements,
    cell: cell,
    style: style,
    viewport: viewport,
    pictureRect: picture,
    numbersSize: numbersSize,
    textScale: textScale,
  );
  if (placement == null || !placement.usable) return null;
  final content = castBeatContentRect(
    placements: placements,
    cell: cell,
    style: style,
    viewport: viewport,
    textScale: textScale,
  );
  if (content == null) return null;
  final canvas = beatNumbersCanvasSize(
    contentSize: content.size,
    numbersSize: numbersSize,
    style: style,
    textScale: textScale,
  );
  final scale = beatNumbersScaleInContent(
    contentSize: content.size,
    style: style,
  );
  if (!canvas.width.isFinite || !canvas.height.isFinite) return null;
  return (
    placement: placement,
    overlay: CastBeatCountOverlay(
      rows: rows,
      centerX: placement.centerX,
      centerY: placement.centerY,
      widthFraction: placement.widthFraction,
      heightFraction: placement.heightFraction,
      // 惰性：真正画字是渲染编排落盘那一刻（与贴纸同款）。
      imageBytesOf: (index) => renderCastBeatSheet(
        text: rows[index].text,
        canvasLogicalSize: canvas,
        scale: scale,
        textScaler: textScaler,
      ),
    ),
  );
}

/// 读各域现值为一份渲染请求。
///
/// [globalMirrored] 由调用方传（全局镜像的现值住在播放页的镜像控制器上，
/// 不在 provider 里）。
///
/// 局部镜像片段在此**读一次**、喂两处：标注指纹与 [CastRenderRequest
/// .mirrorFragments]（画面滤镜链的镜像闸门按它成窗）。**取景**同样在此读一次、
/// 喂两处：设置快照的规范串（缓存键）与 [CastRenderRequest.framingSelection]
/// （画面链的裁切窗口）。**备注**同样读一次、喂三处：标注指纹、
/// [CastRenderRequest.stickers]（第二路输入）与设置快照里的**尺寸记号**
/// （`stickerOverlay`；尺寸分数在这一处现算，不在指纹里——见
/// [castStickerOverlayToken]）。**数拍层**（`#30`）同样读一次、喂两处：
/// 设置快照里的落位记号（缓存键）与 [CastRenderRequest.beatOverlay]。**范围**
/// （`#37`）同样从这一份 timeline 读：首线 / 尾线进 [CastRenderRequest.range]
/// （画面链的 `trim` 与音轨链的 `atrim` 按它成窗），而首尾区间本来就在标注
/// 指纹里——两处读的是同一个值对象的同两个字段，改首尾线即换键。渲染参数
/// 与上屏取值因此读的是同一份取值，不是两处各自读一遍、各自对齐的口径。
///
/// [pictureRect] 是**上屏画面矩形**（取景后那一块）的屏幕矩形：贴纸的尺寸分数
/// 按它归一化，数拍层的落位也按它归一化。量不到（null / 空）时画面类的贴纸与
/// 数拍层整批不装。
///
/// [beatPlacements] / [beatCell] / [beatViewport] 是数拍浮层在手机上的四格记忆
/// 与当前视口（`MetronomeOverlayController` 的现读值），落位从它们算起。
///
/// [resolution] 是这次渲染的**分辨率档**（#36）：由准备面板按编码器能力三态
/// 定（保证 1× = 源档，不保证与问不到 = 720p），在这里原样进请求——它是请求的
/// 一维，因此也进缓存键。
CastRenderRequest castRenderRequestFor(
  CastRenderRead read, {
  required String videoPath,
  required String videoId,
  required bool globalMirrored,
  required CastRenderChoices choices,
  CastSpeedTier speedTier = CastSpeedTier.full,
  CastRenderResolution resolution = CastRenderResolution.source,
  Rect? pictureRect,
  TextScaler textScaler = TextScaler.noScaling,
  OverlayPlacements? beatPlacements,
  OverlayPlacementCell beatCell = OverlayPlacementCell.portraitNormal,
  Size? beatViewport,
}) {
  final timeline = read(annotationTimelineProvider);
  final grid = read(beatGridProvider);
  final sourceId = read(effectiveMetronomeSourceIdProvider);
  final halfBeatEnabled = read(metronomeHalfBeatEnabledProvider);
  final mirrorFragments = read(localMirrorFragmentsProvider);
  // 取景读**一次**，喂两处：缓存键的规范串与画面链的裁切窗口。两处同源，
  // 与上屏（`player_page.dart` 的画面件）取的也是同一个 provider 取值。
  final framing = read(framingStateProvider).source;
  // 备注与名册各读**一次**、喂三处：指纹（含名册取色）、第二路输入（贴纸）
  // 与设置快照里的**尺寸记号**（尺寸分数是下面刚算出来的，不在指纹里）。
  final notes = read(noteStickersProvider);
  final roster = read(dancerRosterProvider);
  final stickers = choices.picture
      ? buildCastStickers(
          notes: notes,
          rosterColors: noteMentionRosterColors(roster),
          pictureSize: pictureRect?.size ?? Size.zero,
          textScaler: textScaler,
        )
      : const <CastSticker>[];
  final beat = buildCastBeatOverlay(
    read: read,
    duration: timeline.videoDuration,
    choices: choices,
    pictureRect: pictureRect,
    textScaler: textScaler,
    placements: beatPlacements,
    cell: beatCell,
    viewport: beatViewport,
  );

  return CastRenderRequest(
    videoPath: videoPath,
    videoId: videoId,
    duration: timeline.videoDuration,
    choices: choices,
    speedTier: speedTier,
    resolution: resolution,
    settings: CastRenderSettings(
      globalMirrored: globalMirrored,
      localMirrorEnabled: read(localMirrorEnabledProvider),
      beatCountVisible: read(beatOverlayContentVisibleProvider),
      beatAnimationStyle: read(beatAnimationStyleProvider).name,
      beatOverlay: beat?.placement.token ?? '',
      stickerOverlay: castStickerOverlayToken(stickers),
      framing: castFramingToken(framing),
      halfBeatSoundEnabled: halfBeatEnabled,
      metronomeVolumePercent: read(metronomeVolumeProvider),
      songLoudnessBaseline: read(songLoudnessBaselineProvider),
      metronomeSourceId: sourceId,
    ),
    annotationFingerprint: castAnnotationFingerprint(
      CastAnnotationFacts(
        timeline: timeline,
        notes: notes,
        mirrorFragments: mirrorFragments,
        roster: roster,
        beatGrid: read(beatTrackStateProvider).grid,
      ),
    ),
    mirrorFragments: mirrorFragments,
    framingSelection: framing,
    stickers: stickers,
    beatOverlay: beat?.overlay,
    // **范围**（#37）：首线 → 尾线，从**这一份** timeline 读（与标注指纹读的是
    // 同一个值对象的那两个字段）。整片时照给——「整片不装节点」由
    // `cast_range_gate.dart` 的 `castRangeActive` 判，装配处不做第二次判断。
    range: CastRange(start: timeline.rangeStart, end: timeline.rangeEnd),
    beatClicks: buildCastBeatClicks(
      grid: grid,
      source: metronomeSourceEntryOfId(sourceId),
      duration: timeline.videoDuration,
      volumeOf: read(metronomePlayVolumeProvider),
      halfBeatLines: [for (final line in timeline.halfBeatLines) line.position],
      halfBeatEnabled: halfBeatEnabled,
    ),
  );
}
