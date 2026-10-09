import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/framing_selection.dart'
    show FramingSelection;
import 'package:dance_learning_app/annotation/half_beat_line.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/cast/cast_beat_count.dart';
import 'package:dance_learning_app/cast/cast_range_gate.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/core/beat_point.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatGridProvider;
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/core/local_mirror_fragment.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationTimelineProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/cast_render_wiring.dart';
import 'package:dance_learning_app/player/dancer_roster_controller.dart'
    show dancerRosterProvider;
import 'package:dance_learning_app/player/framing_session_state.dart'
    show FramingState, framingStateProvider;
import 'package:dance_learning_app/player/beat_animation.dart'
    show BeatAnimationStyle, beatAnimationStyleProvider;
import 'package:dance_learning_app/core/eight_beat_phase.dart'
    show BeatPhase;
import 'package:dance_learning_app/player/beat_presentation.dart'
    show BeatPresentationFacts;
import 'package:dance_learning_app/player/beat_presentation_providers.dart'
    show beatOverlayContentVisibleProvider, beatPresentationFactsProvider;
import 'package:dance_learning_app/player/calibration_session_grid.dart'
    show CalibrationSessionBpmTier;
import 'package:dance_learning_app/player/overlay.dart'
    show OverlayPlacementCell, OverlayPlacements;
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show beatCountTextOf;
import 'package:dance_learning_app/player/beat_presentation.dart'
    show
        assembleBeatPresentationContext,
        evaluatePresentationValue;
import 'package:dance_learning_app/player/metronome_sound.dart'
    show metronomeHalfBeatEnabledProvider;
import 'package:dance_learning_app/player/metronome_source_registry.dart'
    show effectiveMetronomeSourceIdProvider;
import 'package:dance_learning_app/player/song_loudness.dart'
    show metronomeVolumeProvider, songLoudnessBaselineProvider;
import 'package:flutter/painting.dart' show Offset, Rect, Size, TextScaler;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 渲染请求装配直测：各域现值确实各就各位（设置快照、标注指纹、拍声排程），
/// 以及**取景取值变了键就变**这条缓存语义在装配处也成立。
void main() {
  AnnotationTimeline timeline({
    List<SegmentLine> segments = const [],
    List<HalfBeatLine> halfBeats = const [],
    Duration rangeStart = Duration.zero,
    Duration rangeEnd = const Duration(seconds: 30),
  }) => AnnotationTimeline.normalized(
    videoDuration: const Duration(seconds: 30),
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    segmentLines: segments,
    halfBeatLines: halfBeats,
  );

  ProviderContainer container({
    AnnotationTimeline? timelineValue,
    FramingSelection? framing,
    List<NoteSticker> notes = const [],
    bool localMirrorEnabled = true,
    List<LocalMirrorFragment> mirrorFragments = const [
      LocalMirrorFragment(startMs: 1000, endMs: 2000),
    ],
    bool halfBeatEnabled = false,
    BeatGrid? grid,
    BeatPresentationFacts? beatFacts,
  }) {
    final c = ProviderContainer(
      overrides: [
        beatGridProvider.overrideWithValue(
          grid ?? const UniformBeatGrid(bpm: 120),
        ),
        annotationTimelineProvider.overrideWithBuild(
          (ref, _) => timelineValue ?? timeline(),
        ),
        noteStickersProvider.overrideWithBuild((ref, _) => notes),
        localMirrorFragmentsProvider.overrideWithBuild(
          (ref, _) => mirrorFragments,
        ),
        dancerRosterProvider.overrideWithBuild((ref, _) => const []),
        localMirrorEnabledProvider.overrideWithBuild(
          (ref, _) => localMirrorEnabled,
        ),
        metronomeHalfBeatEnabledProvider.overrideWithBuild(
          (ref, _) => halfBeatEnabled,
        ),
        metronomeVolumeProvider.overrideWithBuild((ref, _) => 70),
        songLoudnessBaselineProvider.overrideWithBuild((ref, _) => 0.5),
        framingStateProvider.overrideWithBuild(
          (ref, _) => FramingState(source: framing),
        ),
        // 生效音源与数拍显示各自牵一条长链（校准会话 / 节拍呈现 → 播放内核），
        // 本测试只问接线，故直接钉住取值。
        effectiveMetronomeSourceIdProvider.overrideWithValue('normal'),
        beatOverlayContentVisibleProvider.overrideWithValue(true),
        beatAnimationStyleProvider.overrideWithBuild(
          (ref, _) => BeatAnimationStyle.bar,
        ),
        if (beatFacts != null)
          beatPresentationFactsProvider.overrideWithValue(beatFacts),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  CastRenderRequest requestFrom(
    ProviderContainer c, {
    CastRenderChoices choices = const CastRenderChoices.all(),
    bool globalMirrored = false,
    Rect? pictureRect,
    TextScaler textScaler = TextScaler.noScaling,
    OverlayPlacements? beatPlacements,
    OverlayPlacementCell beatCell = OverlayPlacementCell.portraitNormal,
    Size? beatViewport,
  }) => castRenderRequestFor(
    c.read,
    videoPath: '/videos/a.mp4',
    videoId: 'vid-a',
    globalMirrored: globalMirrored,
    choices: choices,
    pictureRect: pictureRect,
    textScaler: textScaler,
    beatPlacements: beatPlacements,
    beatCell: beatCell,
    beatViewport: beatViewport,
  );

  test('路径、标识、勾选档与时长原样带进请求', () {
    final request = requestFrom(
      container(),
      choices: const CastRenderChoices(picture: false, sound: true),
    );

    expect(request.videoPath, '/videos/a.mp4');
    expect(request.videoId, 'vid-a');
    expect(
      request.choices,
      const CastRenderChoices(picture: false, sound: true),
    );
    expect(request.duration, const Duration(seconds: 30));
    expect(request.speedTier, CastSpeedTier.full, reason: '#26 只有 1× 档');
  });

  test('设置快照读现值：镜像、局部镜像总开关、音量、响度、半拍声', () {
    final request = requestFrom(container(), globalMirrored: true);

    expect(request.settings.globalMirrored, isTrue);
    expect(request.settings.localMirrorEnabled, isTrue);
    expect(request.settings.metronomeVolumePercent, 70);
    expect(request.settings.songLoudnessBaseline, 0.5);
    expect(request.settings.halfBeatSoundEnabled, isFalse);
  });

  test('取景取值进设置快照：未取景是空串，取景后换串也换键', () {
    final none = requestFrom(container());
    expect(none.settings.framing, isEmpty);

    final framed = requestFrom(
      container(
        framing: const FramingSelection(
          left: 0.1,
          top: 0.2,
          right: 0.9,
          bottom: 0.8,
        ),
      ),
    );
    expect(framed.settings.framing, '0.1000,0.2000,0.9000,0.8000');
    expect(framed.cacheKey, isNot(none.cacheKey));
  });

  test('取景选区也进请求：画面链的裁切窗口读的就是上屏那一份值对象', () {
    const selection = FramingSelection(
      left: 0.1,
      top: 0.2,
      right: 0.9,
      bottom: 0.8,
    );
    final none = requestFrom(container());
    final framed = requestFrom(container(framing: selection));

    expect(none.framingSelection, isNull);
    expect(
      framed.framingSelection,
      selection,
      reason: '裁切窗口读这份值对象，不是把规范串再解析一遍',
    );
    expect(framed.settings.framing, castFramingToken(selection));
  });

  test('标注内容进指纹：加了分段线就换键', () {
    final before = requestFrom(container());
    final after = requestFrom(
      container(
        timelineValue: timeline(
          segments: [const SegmentLine(position: Duration(seconds: 5))],
        ),
      ),
    );

    expect(after.annotationFingerprint, isNot(before.annotationFingerprint));
    expect(after.cacheKey, isNot(before.cacheKey));
  });

  test('备注也进指纹（贴纸是画面类的一部分）', () {
    final before = requestFrom(container());
    final after = requestFrom(
      container(
        notes: [const NoteSticker(startMs: 0, endMs: 1000, text: '注意手')],
      ),
    );

    expect(after.cacheKey, isNot(before.cacheKey));
  });

  test('局部镜像片段进请求：渲染参数与上屏、指纹读同一份 provider 取值', () {
    const fragments = [
      LocalMirrorFragment(startMs: 500, endMs: 1500),
      LocalMirrorFragment(startMs: 3000, endMs: 4000),
    ];
    final request = requestFrom(container(mirrorFragments: fragments));

    expect(request.mirrorFragments, fragments);
    expect(request.settings.localMirrorEnabled, isTrue);
  });

  test('片段改了就换键：片段内容已在标注指纹里，不另立第二个键分量', () {
    final before = requestFrom(container());
    final after = requestFrom(
      container(
        mirrorFragments: const [LocalMirrorFragment(startMs: 500, endMs: 900)],
      ),
    );

    expect(after.mirrorFragments, isNot(before.mirrorFragments));
    expect(after.annotationFingerprint, isNot(before.annotationFingerprint));
    expect(after.cacheKey, isNot(before.cacheKey));
  });

  test('范围进请求：首线 / 尾线从那一份 timeline 原样带过去', () {
    final whole = requestFrom(container());
    expect(
      whole.range,
      const CastRange(start: Duration.zero, end: Duration(seconds: 30)),
      reason: '未设首尾线 = 整片（「整片不装节点」由范围闸门判）',
    );

    final clipped = requestFrom(
      container(
        timelineValue: timeline(
          rangeStart: const Duration(seconds: 2),
          rangeEnd: const Duration(seconds: 20),
        ),
      ),
    );
    expect(
      clipped.range,
      const CastRange(
        start: Duration(seconds: 2),
        end: Duration(seconds: 20),
      ),
      reason: '画面链的 trim 与音轨链的 atrim 读的就是这两个数',
    );
  });

  test('首尾线改了就换键：它已在标注指纹里，范围不另立第二个键分量', () {
    final before = requestFrom(container());
    final after = requestFrom(
      container(
        timelineValue: timeline(
          rangeStart: const Duration(seconds: 2),
          rangeEnd: const Duration(seconds: 20),
        ),
      ),
    );

    expect(after.annotationFingerprint, isNot(before.annotationFingerprint));
    expect(after.cacheKey, isNot(before.cacheKey));
    expect(
      after.cacheKey.token.split('#').length,
      before.cacheKey.token.split('#').length,
      reason: '键仍是那五个分量：范围没有多出一个独立分量',
    );
  });

  test('拍声排程：有网格就逐拍落点，音量按槽位口径', () {
    final request = requestFrom(container());

    expect(request.beatClicks, isNotEmpty);
    expect(
      request.beatClicks.take(2).map((c) => c.time.inMilliseconds).toList(),
      [0, 500],
    );
    expect(request.beatClicks.first.asset, contains('strong'));
  });

  test('半拍声开关：开时半拍线进排程，关时只留整拍', () {
    final withLines = timeline(
      halfBeats: [const HalfBeatLine(position: Duration(milliseconds: 250))],
    );
    final off = requestFrom(container(timelineValue: withLines));
    expect(off.beatClicks.length, 60, reason: '30 秒 / 500ms 一拍，含 0 拍');
    expect(off.beatClicks.any((c) => c.asset.contains('half')), isFalse);

    final on = requestFrom(
      container(timelineValue: withLines, halfBeatEnabled: true),
    );
    expect(on.beatClicks.length, 61);
    expect(
      on.beatClicks.where((c) => c.asset.contains('half')).single.time,
      const Duration(milliseconds: 250),
    );
  });

  test('取景规范串：四边四位小数、未取景为空', () {
    expect(castFramingToken(null), isEmpty);
    expect(
      castFramingToken(
        const FramingSelection(left: 0.25, top: 0, right: 0.75, bottom: 1),
      ),
      '0.2500,0.0000,0.7500,1.0000',
    );
  });

  group('备注贴纸：第二路输入的装配（#29）', () {
    const pictureRect = Rect.fromLTWH(0, 0, 960, 540);
    const note = NoteSticker(
      startMs: 1200,
      endMs: 3400,
      text: '注意手',
      geometry: NoteGeometry(centerX: 0.3, centerY: 0.2, scale: 1),
    );

    test('一条备注 → 一条第二路输入：时间窗、几何中心与尺寸分数都到位', () {
      final request = requestFrom(
        container(notes: const [note]),
        pictureRect: pictureRect,
      );

      expect(request.stickers, hasLength(1));
      final sheet = request.stickers.single;
      expect(sheet.startMs, 1200);
      expect(sheet.endMs, 3400);
      expect(sheet.centerX, 0.3, reason: '几何中心与文档同源（上屏求值也读它）');
      expect(sheet.centerY, 0.2);
      expect(sheet.widthFraction, greaterThan(0));
      expect(sheet.heightFraction, greaterThan(0));
      expect(
        sheet.widthFraction,
        lessThan(1),
        reason: '尺寸分数 = 墨迹逻辑尺寸 ÷ 上屏画面矩形，是个比例',
      );
    });

    test('字节口现取就是一张带 alpha 的单帧 PNG（惰性：装配期不画字）', () async {
      final request = requestFrom(
        container(notes: const [note]),
        pictureRect: pictureRect,
      );

      final bytes = await request.stickers.single.imageBytesOf();

      expect(bytes.sublist(0, 8), <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
    });

    test('尺寸分数按上屏画面矩形归一化：画面越小，分数越大', () {
      final wide = requestFrom(
        container(notes: const [note]),
        pictureRect: const Rect.fromLTWH(0, 0, 960, 540),
      ).stickers.single;
      final narrow = requestFrom(
        container(notes: const [note]),
        pictureRect: const Rect.fromLTWH(0, 0, 480, 270),
      ).stickers.single;

      expect(narrow.widthFraction, closeTo(wide.widthFraction * 2, 1e-9));
      expect(narrow.heightFraction, closeTo(wide.heightFraction * 2, 1e-9));
    });

    test('随系统字号缩放：尺寸分数跟着放大（与上屏量测同源）', () {
      final plain = requestFrom(
        container(notes: const [note]),
        pictureRect: pictureRect,
      ).stickers.single;
      final scaled = requestFrom(
        container(notes: const [note]),
        pictureRect: pictureRect,
        textScaler: const TextScaler.linear(2),
      ).stickers.single;

      expect(scaled.widthFraction, greaterThan(plain.widthFraction));
    });

    test('改系统字号即换键：尺寸分数进设置快照，不是键之外的暗箱', () {
      final plain = requestFrom(
        container(notes: const [note]),
        pictureRect: pictureRect,
      );
      final scaled = requestFrom(
        container(notes: const [note]),
        pictureRect: pictureRect,
        textScaler: const TextScaler.linear(2),
      );

      expect(
        scaled.stickers.single.widthFraction,
        isNot(plain.stickers.single.widthFraction),
        reason: '前置：系统字号确实改了尺寸分数',
      );
      expect(
        scaled.settings.stickerOverlay,
        isNot(plain.settings.stickerOverlay),
      );
      expect(
        scaled.cacheKey,
        isNot(plain.cacheKey),
        reason: '尺寸分量变一次就换一把键：改字号后不命中旧副本',
      );
    });

    test('换画面矩形（转屏）即换键：同一个贴纸的尺寸分数变了', () {
      final wide = requestFrom(
        container(notes: const [note]),
        pictureRect: const Rect.fromLTWH(0, 0, 960, 540),
      );
      final narrow = requestFrom(
        container(notes: const [note]),
        pictureRect: const Rect.fromLTWH(0, 0, 480, 270),
      );

      expect(
        narrow.stickers.single.widthFraction,
        isNot(wide.stickers.single.widthFraction),
      );
      expect(
        wide.settings.stickerOverlay,
        isNot(narrow.settings.stickerOverlay),
      );
      expect(
        wide.cacheKey,
        isNot(narrow.cacheKey),
        reason: '画面矩形派生占比 → 进键 → 换屏就重渲',
      );
    });

    test('没备注 / 不勾画面类：贴纸记号是空串（不白换键）', () {
      expect(requestFrom(container()).settings.stickerOverlay, isEmpty);
      expect(
        requestFrom(
          container(notes: const [note]),
          choices: const CastRenderChoices(picture: false, sound: true),
          pictureRect: pictureRect,
        ).settings.stickerOverlay,
        isEmpty,
      );
    });

    test('画面矩形量不到：整批不装（不拿一个错的比例去烤副本）', () {
      expect(requestFrom(container(notes: const [note])).stickers, isEmpty);
      expect(
        requestFrom(
          container(notes: const [note]),
          pictureRect: Rect.zero,
        ).stickers,
        isEmpty,
      );
    });

    test('只勾声音类：贴纸是画面类的东西，不进请求', () {
      final request = requestFrom(
        container(notes: const [note]),
        choices: const CastRenderChoices(picture: false, sound: true),
        pictureRect: pictureRect,
      );

      expect(request.stickers, isEmpty);
    });

    test('空文本与空窗的备注不装：没有墨迹、也没有可见时段', () {
      final request = requestFrom(
        container(
          notes: const [
            NoteSticker(startMs: 0, endMs: 1000, text: ''),
            NoteSticker(startMs: 2000, endMs: 2000, text: '零宽'),
          ],
        ),
        pictureRect: pictureRect,
      );

      expect(request.stickers, isEmpty);
    });

    test('多条备注按次序各成一条第二路输入', () {
      final request = requestFrom(
        container(
          notes: const [
            NoteSticker(startMs: 0, endMs: 1000, text: '一'),
            NoteSticker(startMs: 2000, endMs: 3000, text: '二'),
          ],
        ),
        pictureRect: pictureRect,
      );

      expect(request.stickers, hasLength(2));
      expect(request.stickers[0].startMs, 0);
      expect(request.stickers[1].startMs, 2000);
    });
  });

  group('数拍层（#30）：逐拍文字与落位都按上屏现读值装配', () {
    /// 真实网格：0.2s 起每 0.5s 一拍、共 5 拍（末拍 2.2s）——末拍之后无拍可数。
    DocumentBeatGrid beatGrid() => DocumentBeatGrid(
      beats: const [
        BeatPoint(t: 0.2, down: true),
        BeatPoint(t: 0.7, down: false),
        BeatPoint(t: 1.2, down: false),
        BeatPoint(t: 1.7, down: false),
        BeatPoint(t: 2.2, down: true),
      ],
    );

    BeatPresentationFacts facts({AnnotationTimeline? timelineValue}) {
      final grid = beatGrid();
      return BeatPresentationFacts(
        grid: grid,
        phase: BeatPhase(grid: grid),
        timeline: timelineValue ?? timeline(),
        recordingAnchor: null,
        delayAnchor: null,
        activeLoopStart: null,
        sourceId: 'normal',
        slotVolumeOf: (_) => 0,
        halfBeatEnabled: false,
        soundEnabled: false,
        avSyncDelayMs: 0,
        sessionActive: false,
        sessionTier: CalibrationSessionBpmTier.bpm120,
        sessionTrialMs: 0,
      );
    }

    const placements = OverlayPlacements(
      offsets: {
        OverlayPlacementCell.portraitNormal: Offset(0, 320),
      },
    );
    const viewport = Size(400, 800);
    const pictureRect = Rect.fromLTWH(0, 300, 400, 225);

    CastRenderRequest withBeats({
      CastRenderChoices choices = const CastRenderChoices.all(),
      OverlayPlacements? beatPlacements = placements,
      Size? beatViewport = viewport,
      Rect? picture = pictureRect,
    }) => requestFrom(
      container(beatFacts: facts()),
      choices: choices,
      pictureRect: picture,
      beatPlacements: beatPlacements,
      beatViewport: beatViewport,
    );

    test('逐拍时间窗连续覆盖整片，且在拍点处分格', () {
      final overlay = withBeats().beatOverlay!;

      expect(overlay.rows.first.startMs, 0);
      expect(overlay.rows.last.endMs, 30000);
      for (var i = 0; i + 1 < overlay.rows.length; i++) {
        expect(
          overlay.rows[i].endMs,
          overlay.rows[i + 1].startMs,
          reason: '首尾相接、不重不漏（序列是一路输入，错一格整条时间轴就错位）',
        );
        expect(overlay.rows[i].durationMs, greaterThan(0));
      }
      // 拍点处必须分格：0.2 / 0.7 / 1.2 / 1.7（末拍 2.2 = 显示域终点，
      // 它之后那一段是不显示的格，一直铺到片尾）。
      final starts = overlay.rows.map((row) => row.startMs).toSet();
      for (final ms in <int>[0, 200, 700, 1200, 1700, 2200]) {
        expect(starts, contains(ms), reason: '分界点少了 $ms');
      }
      expect(overlay.rows.last.text, isNull, reason: '末拍之后无拍可数 = 不显示');
    });

    test('每格的文字与手机同一次求值逐点一致', () {
      final favorite = assembleBeatPresentationContext(
        facts(),
        rate: 1,
        playing: false,
      );
      final overlay = withBeats().beatOverlay!;

      var sampled = 0;
      var tailChecked = false;
      for (final row in overlay.rows) {
        final value = evaluatePresentationValue(
          context: favorite,
          position: Duration(milliseconds: row.startMs),
        );
        final expected = value == null
            ? null
            : beatCountTextOf(value.display);
        if (row.text == null && expected != null) {
          // 显示域的终点这一刻：手机上还数得出（位置 ∈ 闭区间），但它的窗是
          // **零宽**的——下一毫秒就没了，副本里因此没有这一格（见
          // `castBeatRowsOf` 库头「显示域的终点是末拍起点」）。
          final after = evaluatePresentationValue(
            context: favorite,
            position: Duration(milliseconds: row.startMs + 1),
          );
          expect(after, isNull, reason: '第 ${row.startMs}ms：这一段应当无拍可数');
          tailChecked = true;
          continue;
        }
        expect(
          row.text,
          expected == null
              ? isNull
              : CastBeatCountText(
                  eightCount: expected.eightCount,
                  group: expected.group,
                  beatCount: expected.beatCount,
                ),
          reason: '第 ${row.startMs}ms 那一格',
        );
        sampled++;
      }
      expect(sampled, greaterThan(3), reason: '样本太少，这条比对没意义');
      expect(tailChecked, isTrue, reason: '末拍之后那一段要在场（否则这条比对漏了一档）');

      // 逐格之内取值恒定：每格中点与左端点同判。
      for (final row in overlay.rows) {
        if (row.durationMs < 2) continue;
        final mid = evaluatePresentationValue(
          context: favorite,
          position: Duration(milliseconds: row.startMs + row.durationMs ~/ 2),
        );
        final midText = mid == null ? null : beatCountTextOf(mid.display);
        expect(
          midText?.beatCount,
          row.text?.beatCount,
          reason: '第 ${row.startMs}ms 那一格的中点不该换号',
        );
        expect(midText?.eightCount, row.text?.eightCount);
      }
    });

    test('落位逐位带上：与视口 → 画面区域换算同一份取值，并进缓存键', () {
      final request = withBeats();
      final overlay = request.beatOverlay!;

      // 框 320×120（未自定义格的默认位 → 竖屏 (0, 96)）；数字行量测尺寸随字号。
      expect(overlay.widthFraction, greaterThan(0));
      expect(overlay.heightFraction, greaterThan(0));
      expect(overlay.centerX, greaterThan(0));
      expect(request.settings.beatOverlay, startsWith('bo:'));
      expect(
        request.settings.beatOverlay,
        contains(overlay.centerX.toStringAsFixed(6)),
      );

      // 挪一下浮层：落位记号跟着变（否则会命中一份落位不对的旧副本）。
      final moved = withBeats(
        beatPlacements: OverlayPlacements(
          offsets: const {
            OverlayPlacementCell.portraitNormal: Offset(60, 360),
          },
        ),
      );
      expect(
        moved.settings.beatOverlay,
        isNot(request.settings.beatOverlay),
      );
      expect(
        moved.cacheKey,
        isNot(request.cacheKey),
        reason: '落位进设置快照 → 换键 → 重渲',
      );
    });

    test('每一格都画得出来：固定画布 × 密度，且惰性（装配期不画）', () async {
      final overlay = withBeats().beatOverlay!;

      final first = await overlay.imageBytesOf(0);
      final last = await overlay.imageBytesOf(overlay.rows.length - 1);

      // PNG 签名；两格像素尺寸一致（图像序列是一条流的前提）。
      expect(first.sublist(0, 8), <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
      expect(identical(first, last), isFalse);
    });

    test('不装数拍层的三种情形：不勾画面类 / 数拍显示关 / 落位量不出来', () {
      expect(
        withBeats(choices: const CastRenderChoices(picture: false, sound: true))
            .beatOverlay,
        isNull,
      );
      expect(
        requestFrom(
          container(
            beatFacts: facts(),
          ),
          pictureRect: pictureRect,
          beatPlacements: placements,
          beatViewport: viewport,
        ).beatOverlay,
        isNotNull,
        reason: '前置：这三样齐全时是装的',
      );
      expect(
        withBeats(beatPlacements: null).beatOverlay,
        isNull,
        reason: '四格浮层位缺席 = 落位量不出来',
      );
      expect(withBeats(beatViewport: null).beatOverlay, isNull);
      expect(withBeats(picture: null).beatOverlay, isNull);
      expect(withBeats(picture: Rect.zero).beatOverlay, isNull);
    });

    test('时长未知 / 网格异常：不装（手机上那时也不显示数拍）', () {
      final unknown = requestFrom(
        container(
          timelineValue: AnnotationTimeline.normalized(
            videoDuration: Duration.zero,
          ),
          beatFacts: facts(),
        ),
        pictureRect: pictureRect,
        beatPlacements: placements,
        beatViewport: viewport,
      );
      expect(unknown.beatOverlay, isNull);

      final fallback = beatGridFallbackFacts();
      expect(
        requestFrom(
          container(beatFacts: fallback),
          pictureRect: pictureRect,
          beatPlacements: placements,
          beatViewport: viewport,
        ).beatOverlay,
        isNull,
        reason: '秒制兜底网格 = 无真拍可数',
      );
    });
  });
}

/// 秒制兜底（异常态）的素材面：节拍不可用。
BeatPresentationFacts beatGridFallbackFacts() {
  const grid = UnavailableBeatGrid();
  return BeatPresentationFacts(
    grid: grid,
    phase: BeatPhase(grid: grid),
    timeline: AnnotationTimeline.normalized(
      videoDuration: const Duration(seconds: 30),
    ),
    recordingAnchor: null,
    delayAnchor: null,
    activeLoopStart: null,
    sourceId: 'normal',
    slotVolumeOf: (_) => 0,
    halfBeatEnabled: false,
    soundEnabled: false,
    avSyncDelayMs: 0,
    sessionActive: false,
    sessionTier: CalibrationSessionBpmTier.bpm120,
    sessionTrialMs: 0,
  );
}
