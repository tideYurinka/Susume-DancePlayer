import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        LocalMirrorEnabledModel,
        LocalMirrorFragmentsModel,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider;
import 'package:dance_learning_app/player/surface_face_assembly.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 画面方向快照的装配与下发：装配函数直测——
/// 局部镜像两项的现值经 `ProviderScope` 注入读面，不注其它容器、不起播放页。
void main() {
  const baselines = SurfaceBaselines(
    platformPreviewBasis: FaceDirection.original,
    platformSaveBasis: FaceDirection.original,
  );

  /// 经读面求一份快照：局部镜像两项由夹具注入。
  Future<SurfaceDirection> assemble(
    WidgetTester tester, {
    bool globalMirrored = false,
    bool localMirrorEnabled = false,
    List<LocalMirrorFragment> fragments = const [],
    int positionMs = 0,
    bool practiceMirror = false,
    SurfaceBaselines baselinesOverride = baselines,
  }) async {
    late SurfaceDirection value;
    await tester.pumpWidget(
      ProviderScope(
        // 每次求值重挂作用域：局部镜像两项的现值随调用变，须重建提供者。
        key: UniqueKey(),
        overrides: [
          localMirrorEnabledProvider.overrideWith(
            () => _EnabledModel(localMirrorEnabled),
          ),
          localMirrorFragmentsProvider.overrideWith(
            () => _FragmentsModel(fragments),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            value = assembleSurfaceDirection(
              ref,
              globalMirrored: globalMirrored,
              positionMs: positionMs,
              practiceMirror: practiceMirror,
              baselines: baselinesOverride,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return value;
  }

  group('快照装配（逐项入参收成一次求值）', () {
    testWidgets('源视频面 = 全局镜像 ⊕（局部镜像开关 ∧ 片段覆盖当前位置）', (tester) async {
      const fragments = [LocalMirrorFragment(startMs: 1000, endMs: 2000)];

      expect(
        (await assemble(
          tester,
          globalMirrored: true,
        )).directionOf(SurfaceFace.sourceVideo),
        FaceDirection.mirrored,
      );
      // 位置在片段内但开关关：片段整组不参与。
      expect(
        (await assemble(
          tester,
          globalMirrored: true,
          fragments: fragments,
          positionMs: 1500,
        )).directionOf(SurfaceFace.sourceVideo),
        FaceDirection.mirrored,
      );
      // 开关开且位置在片段内：相对全局镜像反相。
      expect(
        (await assemble(
          tester,
          globalMirrored: true,
          localMirrorEnabled: true,
          fragments: fragments,
          positionMs: 1500,
        )).directionOf(SurfaceFace.sourceVideo),
        FaceDirection.original,
      );
      // 半开区间：终点不在覆盖内。
      expect(
        (await assemble(
          tester,
          globalMirrored: true,
          localMirrorEnabled: true,
          fragments: fragments,
          positionMs: 2000,
        )).directionOf(SurfaceFace.sourceVideo),
        FaceDirection.mirrored,
      );
    });

    testWidgets('局部镜像生效取值与源视频面方向同源（画面标识读同一份）', (tester) async {
      const fragments = [LocalMirrorFragment(startMs: 0, endMs: 500)];

      final active = await assemble(
        tester,
        localMirrorEnabled: true,
        fragments: fragments,
        positionMs: 250,
      );
      final inactive = await assemble(
        tester,
        localMirrorEnabled: true,
        fragments: fragments,
        positionMs: 750,
      );

      expect(active.localMirrorActive, isTrue);
      expect(
        active.directionOf(SurfaceFace.sourceVideo),
        FaceDirection.mirrored,
      );
      expect(inactive.localMirrorActive, isFalse);
      expect(
        inactive.directionOf(SurfaceFace.sourceVideo),
        FaceDirection.original,
      );
    });

    testWidgets('练习侧两路方向恒等且锚定平台保存基准（镜像是活输入）', (tester) async {
      const mirroredSave = SurfaceBaselines(
        platformPreviewBasis: FaceDirection.mirrored,
        platformSaveBasis: FaceDirection.mirrored,
      );
      final snapshot = await assemble(
        tester,
        practiceMirror: true,
        baselinesOverride: mirroredSave,
      );

      expect(
        snapshot.directionOf(SurfaceFace.cameraPreview),
        snapshot.directionOf(SurfaceFace.clipPlayback),
      );
      expect(
        snapshot.directionOf(SurfaceFace.clipPlayback),
        FaceDirection.original,
      );
      expect(
        snapshot.surfaceScaleX(SurfaceFace.cameraPreview),
        -1.0,
        reason: '预览面施加缩放 = 自身原始朝向（平台预览基准 = 镜像）⊕ 方向（原相）',
      );
      expect(snapshot.surfaceScaleX(SurfaceFace.clipPlayback), 1.0);
    });
  });
}

/// 局部镜像总开关的现值注入（读面直测用）。
class _EnabledModel extends LocalMirrorEnabledModel {
  _EnabledModel(this._value);

  final bool _value;

  @override
  bool build() => _value;
}

/// 局部镜像片段表的现值注入（读面直测用）。
class _FragmentsModel extends LocalMirrorFragmentsModel {
  _FragmentsModel(this._value);

  final List<LocalMirrorFragment> _value;

  @override
  List<LocalMirrorFragment> build() => _value;
}
