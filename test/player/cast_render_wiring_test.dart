import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/framing_selection.dart'
    show FramingSelection;
import 'package:dance_learning_app/annotation/half_beat_line.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatGridProvider;
import 'package:dance_learning_app/core/beat_grid.dart';
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
import 'package:dance_learning_app/player/beat_presentation_providers.dart'
    show beatOverlayContentVisibleProvider;
import 'package:dance_learning_app/player/metronome_sound.dart'
    show metronomeHalfBeatEnabledProvider;
import 'package:dance_learning_app/player/metronome_source_registry.dart'
    show effectiveMetronomeSourceIdProvider;
import 'package:dance_learning_app/player/song_loudness.dart'
    show metronomeVolumeProvider, songLoudnessBaselineProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 渲染请求装配直测：各域现值确实各就各位（设置快照、标注指纹、拍声排程），
/// 以及**取景取值变了键就变**这条缓存语义在装配处也成立。
void main() {
  AnnotationTimeline timeline({
    List<SegmentLine> segments = const [],
    List<HalfBeatLine> halfBeats = const [],
  }) => AnnotationTimeline.normalized(
    videoDuration: const Duration(seconds: 30),
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
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  CastRenderRequest requestFrom(
    ProviderContainer c, {
    CastRenderChoices choices = const CastRenderChoices.all(),
    bool globalMirrored = false,
  }) => castRenderRequestFor(
    c.read,
    videoPath: '/videos/a.mp4',
    videoId: 'vid-a',
    globalMirrored: globalMirrored,
    choices: choices,
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
}
