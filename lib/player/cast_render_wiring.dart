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

import 'package:flutter/painting.dart' show TextScaler, Size;
import 'package:riverpod/misc.dart' show ProviderListenable;

import '../annotation/framing_selection.dart' show FramingSelection;
import '../annotation/note_sticker.dart' show NoteSticker;
import '../cast/cast_annotation_fingerprint.dart';
import '../cast/cast_render_request.dart';
import '../beat_track_state/beat_track_state.dart'
    show beatGridProvider, beatTrackStateProvider;
import 'annotation_editor.dart'
    show
        annotationTimelineProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'beat_animation.dart' show beatAnimationStyleProvider;
import 'beat_presentation_providers.dart'
    show beatOverlayContentVisibleProvider;
import 'cast_beat_clicks.dart' show buildCastBeatClicks;
import 'cast_sticker_sheet.dart'
    show castStickerSheetLogicalSize, renderCastStickerSheet;
import 'dancer_roster_controller.dart' show dancerRosterProvider;
import 'framing_session_state.dart' show framingStateProvider;
import 'metronome_sound.dart' show metronomeHalfBeatEnabledProvider;
import 'metronome_source_registry.dart'
    show effectiveMetronomeSourceIdProvider, metronomeSourceEntryOfId;
import 'note_sticker_overlay.dart' show noteMentionRosterColors;
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

/// 读各域现值为一份渲染请求。
///
/// [globalMirrored] 由调用方传（全局镜像的现值住在播放页的镜像控制器上，
/// 不在 provider 里）。
///
/// 局部镜像片段在此**读一次**、喂两处：标注指纹与 [CastRenderRequest
/// .mirrorFragments]（画面滤镜链的镜像闸门按它成窗）。**取景**同样在此读一次、
/// 喂两处：设置快照的规范串（缓存键）与 [CastRenderRequest.framingSelection]
/// （画面链的裁切窗口）。**备注**同样读一次、喂两处：标注指纹与
/// [CastRenderRequest.stickers]（贴纸是第二路输入，落位与尺寸按上屏同一份口径
/// 算——见 [buildCastStickers]）。渲染参数与上屏取值因此读的是同一份 provider
/// 取值，不是两处各自读一遍、各自对齐的口径。
///
/// [pictureSize] 是**上屏画面矩形**（取景后那一块）的尺寸：贴纸的尺寸分数按它
/// 归一化。量不到（null / 空）时画面类的贴纸整批不装。
CastRenderRequest castRenderRequestFor(
  CastRenderRead read, {
  required String videoPath,
  required String videoId,
  required bool globalMirrored,
  required CastRenderChoices choices,
  CastSpeedTier speedTier = CastSpeedTier.full,
  Size? pictureSize,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final timeline = read(annotationTimelineProvider);
  final grid = read(beatGridProvider);
  final sourceId = read(effectiveMetronomeSourceIdProvider);
  final halfBeatEnabled = read(metronomeHalfBeatEnabledProvider);
  final mirrorFragments = read(localMirrorFragmentsProvider);
  // 取景读**一次**，喂两处：缓存键的规范串与画面链的裁切窗口。两处同源，
  // 与上屏（`player_page.dart` 的画面件）取的也是同一个 provider 取值。
  final framing = read(framingStateProvider).source;
  // 备注与名册各读**一次**、喂两处：指纹（含名册取色）与第二路输入（贴纸）。
  final notes = read(noteStickersProvider);
  final roster = read(dancerRosterProvider);

  return CastRenderRequest(
    videoPath: videoPath,
    videoId: videoId,
    duration: timeline.videoDuration,
    choices: choices,
    speedTier: speedTier,
    settings: CastRenderSettings(
      globalMirrored: globalMirrored,
      localMirrorEnabled: read(localMirrorEnabledProvider),
      beatCountVisible: read(beatOverlayContentVisibleProvider),
      beatAnimationStyle: read(beatAnimationStyleProvider).name,
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
    stickers: choices.picture
        ? buildCastStickers(
            notes: notes,
            rosterColors: noteMentionRosterColors(roster),
            pictureSize: pictureSize ?? Size.zero,
            textScaler: textScaler,
          )
        : const [],
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
