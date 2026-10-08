import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter_test/flutter_test.dart';

/// 画面方向模块纯值层直测：断言模块对外的取值与读法，不断言实现内部的位表、
/// 缓存或调用次序。已接线的面是**源视频面**（全局镜像 ⊕（局部镜像开关 ∧
/// 片段覆盖当前位置））、**相机预览面**（练习镜像 ⊕ 平台预览基准 ⊕ 基准键）与
/// **片段回放面**（练习镜像 ⊕ 平台保存基准）；素材方向（录像文件面
/// = 平台保存基准）经基线项读出，录像文件面与导出面尚未接进面表。
///
///  的同帧取证把「同一个开关取值下多出来的那一次翻转」裁定给**预览面**
/// （相机通路对前置实时预览做自拍镜像，预览件相对录像文件就是镜像）：相机预览
/// 面自身原始朝向 = 平台预览基准，片段回放面自身原始朝向 = 原相。把
/// **基准键**进表的位置改到相机预览行，于是两路可见方向锚定在**平台保存基准**，
/// 平台预览基准只作为预览面的自身原始朝向进入施加缩放（补偿平台自拍镜像）。
/// 本文件末的「归属裁定」组从两个公开读法反解 R 钉住这条归属。
void main() {
  SurfaceDirection directionOf({
    bool globalMirrored = false,
    bool localMirrorEnabled = true,
    List<LocalMirrorFragment> fragments = const [],
    int positionMs = 0,
    bool practiceMirror = false,
    FaceDirection platformPreviewBasis = FaceDirection.original,
    FaceDirection platformSaveBasis = FaceDirection.original,
  }) => SurfaceDirection(
    moment: SurfaceMoment(
      globalMirrored: globalMirrored,
      localMirrorEnabled: localMirrorEnabled,
      fragments: fragments,
      positionMs: positionMs,
      practiceMirror: practiceMirror,
      baselines: SurfaceBaselines(
        platformPreviewBasis: platformPreviewBasis,
        platformSaveBasis: platformSaveBasis,
      ),
    ),
  );

  /// 以一份**基线项**（录制武装那一刻冻结的那份，或设备事实的当前取值）求值：
  /// 基线项由参数给定，练习镜像是活输入、照常现传。
  SurfaceDirection momentFrom(
    SurfaceBaselines baselines, {
    bool practiceMirror = false,
    int positionMs = 0,
    bool globalMirrored = false,
  }) => SurfaceDirection(
    moment: SurfaceMoment(
      globalMirrored: globalMirrored,
      localMirrorEnabled: true,
      fragments: const [],
      positionMs: positionMs,
      practiceMirror: practiceMirror,
      baselines: baselines,
    ),
  );

  group('源视频面真值表', () {
    test('全局镜像两态、无片段：方向 = 全局镜像', () {
      expect(
        directionOf(globalMirrored: false).directionOf(SurfaceFace.sourceVideo),
        FaceDirection.original,
      );
      expect(
        directionOf(globalMirrored: true).directionOf(SurfaceFace.sourceVideo),
        FaceDirection.mirrored,
      );
    });

    test('片段覆盖位置：局部镜像开关开时相对全局镜像反相', () {
      const fragment = LocalMirrorFragment(startMs: 2000, endMs: 6000);

      // 全局关 + 覆盖 → 镜像；全局开 + 覆盖 → 原相。
      expect(
        directionOf(
          fragments: const [fragment],
          positionMs: 3000,
        ).directionOf(SurfaceFace.sourceVideo),
        FaceDirection.mirrored,
      );
      expect(
        directionOf(
          globalMirrored: true,
          fragments: const [fragment],
          positionMs: 3000,
        ).directionOf(SurfaceFace.sourceVideo),
        FaceDirection.original,
      );
    });

    test('半开区间：起点含、终点不含，区间外按全局镜像', () {
      const fragment = LocalMirrorFragment(startMs: 2000, endMs: 6000);

      for (final (positionMs, expected) in [
        (1999, FaceDirection.original),
        (2000, FaceDirection.mirrored),
        (5999, FaceDirection.mirrored),
        (6000, FaceDirection.original),
      ]) {
        expect(
          directionOf(
            fragments: const [fragment],
            positionMs: positionMs,
          ).directionOf(SurfaceFace.sourceVideo),
          expected,
          reason: '位置 $positionMs 相对半开区间 [2000, 6000) 的判定',
        );
      }
    });

    test('局部镜像总开关关：片段覆盖位置与空隙两态都按全局镜像', () {
      const fragment = LocalMirrorFragment(startMs: 0, endMs: 10000);
      for (final positionMs in [0, 3000, 9999, 10000]) {
        for (final globalMirrored in [true, false]) {
          expect(
            directionOf(
              globalMirrored: globalMirrored,
              localMirrorEnabled: false,
              fragments: const [fragment],
              positionMs: positionMs,
            ).directionOf(SurfaceFace.sourceVideo),
            globalMirrored ? FaceDirection.mirrored : FaceDirection.original,
            reason: '总开关关时位置 $positionMs 只按全局镜像',
          );
        }
      }
    });

    test('多片段并集：任一覆盖即反相，空隙不反相', () {
      const fragments = [
        LocalMirrorFragment(startMs: 0, endMs: 1000),
        LocalMirrorFragment(startMs: 3000, endMs: 4000),
      ];

      for (final (positionMs, expected) in [
        (500, FaceDirection.mirrored),
        (2000, FaceDirection.original),
        (3500, FaceDirection.mirrored),
      ]) {
        expect(
          directionOf(
            fragments: fragments,
            positionMs: positionMs,
          ).directionOf(SurfaceFace.sourceVideo),
          expected,
          reason: '位置 $positionMs 的多片段并集判定',
        );
      }
    });

    test('相邻片段共享端点：前段终点不反相、下一起点当刻反相', () {
      const fragments = [
        LocalMirrorFragment(startMs: 1000, endMs: 2000),
        LocalMirrorFragment(startMs: 2000, endMs: 3000),
      ];

      for (final (positionMs, expected) in [
        (999, FaceDirection.original),
        (1000, FaceDirection.mirrored),
        (1999, FaceDirection.mirrored),
        (2000, FaceDirection.mirrored),
        (2999, FaceDirection.mirrored),
        (3000, FaceDirection.original),
      ]) {
        expect(
          directionOf(
            fragments: fragments,
            positionMs: positionMs,
          ).directionOf(SurfaceFace.sourceVideo),
          expected,
          reason: '位置 $positionMs 相对共享端点 2000 的半开判定',
        );
      }
    });
  });

  group('局部镜像覆盖取值（画面翻转与画面标识共用的一式）', () {
    test('半开区间两端：起点生效、终点不生效', () {
      const fragment = LocalMirrorFragment(startMs: 2000, endMs: 6000);
      for (final (positionMs, expected) in [
        (1999, false),
        (2000, true),
        (5999, true),
        (6000, false),
      ]) {
        expect(
          directionOf(
            fragments: const [fragment],
            positionMs: positionMs,
          ).localMirrorActive,
          expected,
          reason: '位置 $positionMs 相对半开区间 [2000, 6000) 的覆盖取值',
        );
      }
    });

    test('总开关关：区间内也不生效', () {
      const fragment = LocalMirrorFragment(startMs: 0, endMs: 10000);
      for (final positionMs in [0, 3000, 9999]) {
        expect(
          directionOf(
            localMirrorEnabled: false,
            fragments: const [fragment],
            positionMs: positionMs,
          ).localMirrorActive,
          isFalse,
          reason: '总开关关时位置 $positionMs 不生效',
        );
      }
    });

    test('多片段并集：任一覆盖即生效，空隙不生效', () {
      const fragments = [
        LocalMirrorFragment(startMs: 0, endMs: 1000),
        LocalMirrorFragment(startMs: 3000, endMs: 4000),
      ];
      for (final (positionMs, expected) in [
        (500, true),
        (2000, false),
        (3500, true),
      ]) {
        expect(
          directionOf(
            fragments: fragments,
            positionMs: positionMs,
          ).localMirrorActive,
          expected,
          reason: '位置 $positionMs 的多片段并集覆盖取值',
        );
      }
    });

    test('与全局镜像无关：同一位置/片段下全局两态取同一个覆盖取值', () {
      const fragment = LocalMirrorFragment(startMs: 2000, endMs: 6000);
      for (final positionMs in [1000, 3000, 7000]) {
        final off = directionOf(
          fragments: const [fragment],
          positionMs: positionMs,
        ).localMirrorActive;
        final on = directionOf(
          globalMirrored: true,
          fragments: const [fragment],
          positionMs: positionMs,
        ).localMirrorActive;
        expect(on, off, reason: '位置 $positionMs 覆盖取值不读全局镜像');
      }
    });

    test('画面翻转读同一取值：源视频面方向 = 全局镜像 ⊕ 覆盖取值', () {
      // 期望值独立写在这里：覆盖取值真则相对全局镜像反相，假则等于全局镜像。
      const fragment = LocalMirrorFragment(startMs: 2000, endMs: 6000);
      for (final globalMirrored in [true, false]) {
        for (final positionMs in [1000, 3000]) {
          final face = directionOf(
            globalMirrored: globalMirrored,
            fragments: const [fragment],
            positionMs: positionMs,
          );
          final expected = face.localMirrorActive
              ? (globalMirrored
                    ? FaceDirection.original
                    : FaceDirection.mirrored)
              : (globalMirrored
                    ? FaceDirection.mirrored
                    : FaceDirection.original);
          expect(
            face.directionOf(SurfaceFace.sourceVideo),
            expected,
            reason: '全局镜像=$globalMirrored 位置=$positionMs 时方向随覆盖取值反相',
          );
        }
      }
    });
  });

  group('相机预览面真值表', () {
    test('方向 = 练习镜像 ⊕ 平台预览基准 ⊕ 基准键 = 练习镜像 ⊕ 平台保存基准；'
        '施加的缩放 = 平台预览基准 ⊕ 方向（八组合穷举）', () {
      // 期望值独立写在这里（不是复述实现）：锚定在平台保存基准上——基准键
      // = 平台预览基准 ⊕ 平台保存基准，与方向里的平台预览基准相消，于是
      // 方向 = 练习镜像 ⊕ 平台保存基准；该面的自身原始朝向 = 平台预览基准
      // （平台怎么把预览交给应用），故施加的缩放 = 平台预览基准 ⊕ 方向。
      final table =
          <(bool, FaceDirection, FaceDirection), (FaceDirection, double)>{
            (false, FaceDirection.original, FaceDirection.original): (
              FaceDirection.original,
              1,
            ),
            (true, FaceDirection.original, FaceDirection.original): (
              FaceDirection.mirrored,
              -1,
            ),
            (false, FaceDirection.mirrored, FaceDirection.original): (
              FaceDirection.original,
              -1,
            ),
            (true, FaceDirection.mirrored, FaceDirection.original): (
              FaceDirection.mirrored,
              1,
            ),
            (false, FaceDirection.original, FaceDirection.mirrored): (
              FaceDirection.mirrored,
              -1,
            ),
            (true, FaceDirection.original, FaceDirection.mirrored): (
              FaceDirection.original,
              1,
            ),
            (false, FaceDirection.mirrored, FaceDirection.mirrored): (
              FaceDirection.mirrored,
              1,
            ),
            (true, FaceDirection.mirrored, FaceDirection.mirrored): (
              FaceDirection.original,
              -1,
            ),
          };
      for (final entry in table.entries) {
        final face = directionOf(
          practiceMirror: entry.key.$1,
          platformPreviewBasis: entry.key.$2,
          platformSaveBasis: entry.key.$3,
        );
        final label =
            '练习镜像=${entry.key.$1} 平台预览基准=${entry.key.$2} '
            '平台保存基准=${entry.key.$3}';
        expect(
          face.directionOf(SurfaceFace.cameraPreview),
          entry.value.$1,
          reason: '方向：$label',
        );
        expect(
          face.surfaceScaleX(SurfaceFace.cameraPreview),
          entry.value.$2,
          reason: '施加的缩放：$label',
        );
      }
    });

    test('档位语义：两基准两态下都是 开 = 照镜子（镜像）、关 = 原相', () {
      // 档位语义是用户可见判据：相对**录像文件原相**，练习镜像
      // 开 = 照镜子、关 = 原相。它只锚在平台保存基准上，预览基准是原相还是
      // 镜像都不改这条语义（平台自拍镜像由预览面的自身原始朝向补偿）。
      for (final previewBasis in FaceDirection.values) {
        for (final (practiceMirror, expected) in [
          (true, FaceDirection.mirrored),
          (false, FaceDirection.original),
        ]) {
          final face = directionOf(
            practiceMirror: practiceMirror,
            platformPreviewBasis: previewBasis,
            platformSaveBasis: FaceDirection.original,
          );
          for (final which in [
            SurfaceFace.cameraPreview,
            SurfaceFace.clipPlayback,
          ]) {
            expect(
              face.directionOf(which),
              expected,
              reason:
                  '练习镜像=$practiceMirror 平台预览基准=$previewBasis 时 '
                  '$which 的用户可见方向必须是${practiceMirror ? '照镜子' : '原相'}',
            );
          }
        }
      }
    });

    test('相机预览面不读源侧输入：全局镜像 / 局部镜像片段 / 位置都不改它的取值', () {
      const fragments = [LocalMirrorFragment(startMs: 0, endMs: 10000)];
      for (final globalMirrored in [true, false]) {
        for (final localMirrorEnabled in [true, false]) {
          for (final positionMs in [0, 5000, 10000]) {
            expect(
              directionOf(
                globalMirrored: globalMirrored,
                localMirrorEnabled: localMirrorEnabled,
                fragments: fragments,
                positionMs: positionMs,
                practiceMirror: true,
              ).surfaceScaleX(SurfaceFace.cameraPreview),
              -1,
              reason:
                  '源侧局部镜像门不代管练习侧'
                  '（全局镜像=$globalMirrored 总开关=$localMirrorEnabled 位置=$positionMs）',
            );
          }
        }
      }
    });
  });

  group('片段回放面真值表', () {
    test('方向 = 练习镜像 ⊕ 平台保存基准；施加的缩放 = 自身原始朝向 ⊕ 方向'
        '（练习镜像 × 平台预览基准 × 平台保存基准 八组合穷举）', () {
      // 期望值独立写在这里（不是复述实现）：锚定在平台保存基准上——该面不读
      // 平台预览基准（基准键只进相机预览行）；该面自身原始朝向 = 原相。
      // 同帧取证裁定：第二播放源交来的画面就是录像文件的原相，多出来的那
      // 一次翻转归预览面，故施加的缩放 = 该面方向。
      final table =
          <(bool, FaceDirection, FaceDirection), (FaceDirection, double)>{
            (false, FaceDirection.original, FaceDirection.original): (
              FaceDirection.original,
              1,
            ),
            (true, FaceDirection.original, FaceDirection.original): (
              FaceDirection.mirrored,
              -1,
            ),
            (false, FaceDirection.mirrored, FaceDirection.original): (
              FaceDirection.original,
              1,
            ),
            (true, FaceDirection.mirrored, FaceDirection.original): (
              FaceDirection.mirrored,
              -1,
            ),
            (false, FaceDirection.original, FaceDirection.mirrored): (
              FaceDirection.mirrored,
              -1,
            ),
            (true, FaceDirection.original, FaceDirection.mirrored): (
              FaceDirection.original,
              1,
            ),
            (false, FaceDirection.mirrored, FaceDirection.mirrored): (
              FaceDirection.mirrored,
              -1,
            ),
            (true, FaceDirection.mirrored, FaceDirection.mirrored): (
              FaceDirection.original,
              1,
            ),
          };
      for (final entry in table.entries) {
        final face = directionOf(
          practiceMirror: entry.key.$1,
          platformPreviewBasis: entry.key.$2,
          platformSaveBasis: entry.key.$3,
        );
        final label =
            '练习镜像=${entry.key.$1} 平台预览基准=${entry.key.$2} '
            '平台保存基准=${entry.key.$3}';
        expect(
          face.directionOf(SurfaceFace.clipPlayback),
          entry.value.$1,
          reason: '方向：$label',
        );
        expect(
          face.surfaceScaleX(SurfaceFace.clipPlayback),
          entry.value.$2,
          reason: '施加的缩放：$label',
        );
      }
    });

    test('片段回放面不读源侧输入：全局镜像 / 局部镜像总开关 / 片段 / 位置都不改它的取值', () {
      const fragments = [LocalMirrorFragment(startMs: 0, endMs: 10000)];
      for (final globalMirrored in [true, false]) {
        for (final localMirrorEnabled in [true, false]) {
          for (final positionMs in [0, 5000, 10000]) {
            expect(
              directionOf(
                globalMirrored: globalMirrored,
                localMirrorEnabled: localMirrorEnabled,
                fragments: fragments,
                positionMs: positionMs,
                practiceMirror: true,
              ).surfaceScaleX(SurfaceFace.clipPlayback),
              -1,
              reason:
                  '源侧局部镜像门不代管练习侧'
                  '（全局镜像=$globalMirrored 总开关=$localMirrorEnabled 位置=$positionMs）',
            );
          }
        }
      }
    });
  });

  group('素材方向（录像文件面 = 平台保存基准）', () {
    test('四组合穷举：素材方向 = 平台保存基准（基准键只进相机预览行）', () {
      // 期望值独立写在这里（不是复述实现）：素材方向是素材自己的事实，参照系
      // 就是录像文件原相 ⇒ 它就是平台保存基准；基准键是「预览基准相对保存
      // 基准」的落点，不参与素材方向。
      final table = <(FaceDirection, FaceDirection), FaceDirection>{
        (FaceDirection.original, FaceDirection.original):
            FaceDirection.original,
        (FaceDirection.mirrored, FaceDirection.original):
            FaceDirection.original,
        (FaceDirection.original, FaceDirection.mirrored):
            FaceDirection.mirrored,
        (FaceDirection.mirrored, FaceDirection.mirrored):
            FaceDirection.mirrored,
      };
      for (final entry in table.entries) {
        expect(
          SurfaceBaselines(
            platformPreviewBasis: entry.key.$1,
            platformSaveBasis: entry.key.$2,
          ).materialDirection,
          entry.value,
          reason: '素材方向：平台预览基准=${entry.key.$1} 平台保存基准=${entry.key.$2}',
        );
      }
    });

    test('素材方向只读基线项：练习镜像 / 源侧开关 / 片段 / 位置都不改它', () {
      const fragments = [LocalMirrorFragment(startMs: 0, endMs: 10000)];
      const baselines = SurfaceBaselines(
        platformPreviewBasis: FaceDirection.mirrored,
        platformSaveBasis: FaceDirection.original,
      );
      for (final practiceMirror in [true, false]) {
        for (final globalMirrored in [true, false]) {
          for (final positionMs in [0, 5000]) {
            final moment = SurfaceMoment(
              globalMirrored: globalMirrored,
              localMirrorEnabled: true,
              fragments: fragments,
              positionMs: positionMs,
              practiceMirror: practiceMirror,
              baselines: baselines,
            );
            expect(
              moment.baselines.materialDirection,
              FaceDirection.original,
              reason:
                  '素材方向不是练习侧的取值'
                  '（练习镜像=$practiceMirror 全局镜像=$globalMirrored 位置=$positionMs）',
            );
          }
        }
      }
    });

    test('基准键 = 平台预览基准 ⊕ 平台保存基准（四组合穷举）', () {
      final table = <(FaceDirection, FaceDirection), FaceDirection>{
        (FaceDirection.original, FaceDirection.original):
            FaceDirection.original,
        (FaceDirection.mirrored, FaceDirection.original):
            FaceDirection.mirrored,
        (FaceDirection.original, FaceDirection.mirrored):
            FaceDirection.mirrored,
        (FaceDirection.mirrored, FaceDirection.mirrored):
            FaceDirection.original,
      };
      for (final entry in table.entries) {
        expect(
          SurfaceBaselines(
            platformPreviewBasis: entry.key.$1,
            platformSaveBasis: entry.key.$2,
          ).basisKey,
          entry.value,
          reason: '基准键：平台预览基准=${entry.key.$1} 平台保存基准=${entry.key.$2}',
        );
      }
    });
  });

  group('设备级基准键落定两项设备事实', () {
    test('四组合穷举：按设备级键落定后，派生出的基准键就是落定的那一份', () {
      // 期望值独立写在这里（不是复述实现）：基准键 := 平台预览基准 ⊕ 平台保存
      // 基准 ⇒ 平台预览基准 = 基准键 ⊕ 平台保存基准。
      final previewTable = <(FaceDirection, FaceDirection), FaceDirection>{
        (FaceDirection.original, FaceDirection.original):
            FaceDirection.original,
        (FaceDirection.original, FaceDirection.mirrored):
            FaceDirection.mirrored,
        (FaceDirection.mirrored, FaceDirection.original):
            FaceDirection.mirrored,
        (FaceDirection.mirrored, FaceDirection.mirrored):
            FaceDirection.original,
      };
      for (final entry in previewTable.entries) {
        final baselines = SurfaceBaselines.fromBasisKey(
          basisKey: entry.key.$1,
          platformSaveBasis: entry.key.$2,
        );
        expect(
          baselines.platformPreviewBasis,
          entry.value,
          reason:
              '平台预览基准 = 基准键 ⊕ 平台保存基准'
              '（键=${entry.key.$1} 保存基准=${entry.key.$2}）',
        );
        expect(
          baselines.platformSaveBasis,
          entry.key.$2,
          reason: '平台保存基准仍由平台事实给出，不因键改写',
        );
        expect(
          baselines.basisKey,
          entry.key.$1,
          reason:
              '落定后派生出的键回到落定值'
              '（键=${entry.key.$1} 保存基准=${entry.key.$2}）',
        );
      }
    });
  });

  group('归属裁定：多出来的那一次翻转归预览面（同帧取证）', () {
    /// 某面画面件的**自身原始朝向** R —— 由模块的两个公开读法反解
    /// （`F = R ⊕ D` ⇒ `R = F ⊕ D`；固定两个读法，不新增第三个读法，
    /// 故判据从公开读法推）。
    double ownOrientationScale(SurfaceDirection face, SurfaceFace which) =>
        face.surfaceScaleX(which) * face.directionOf(which).scaleX;

    test('相机预览面：自身原始朝向 = 平台预览基准——平台交来的画面就是平台事实', () {
      for (final basis in FaceDirection.values) {
        for (final practiceMirror in [true, false]) {
          expect(
            ownOrientationScale(
              directionOf(
                practiceMirror: practiceMirror,
                platformPreviewBasis: basis,
              ),
              SurfaceFace.cameraPreview,
            ),
            basis.scaleX,
            reason:
                '平台事实=$basis 练习镜像=$practiceMirror：预览面的原始朝向只由'
                '平台事实给出（练习镜像是显示层叠加，不改该面原始朝向）',
          );
        }
      }
    });

    test('片段回放面：自身原始朝向 = 原相——第二播放源交来的画面就是录像文件的原相', () {
      for (final previewBasis in FaceDirection.values) {
        for (final saveBasis in FaceDirection.values) {
          for (final practiceMirror in [true, false]) {
            expect(
              ownOrientationScale(
                directionOf(
                  practiceMirror: practiceMirror,
                  platformPreviewBasis: previewBasis,
                  platformSaveBasis: saveBasis,
                ),
                SurfaceFace.clipPlayback,
              ),
              FaceDirection.original.scaleX,
              reason:
                  '平台预览基准=$previewBasis 平台保存基准=$saveBasis '
                  '练习镜像=$practiceMirror：多出来的那一次翻转归**预览面**'
                  '（平台对前置实时预览做了镜像），回放面不多翻一次',
            );
          }
        }
      }
    });

    test('归属的直接后果：非镜像平台（预览基准 = 原相）上两面施加同一次翻转', () {
      for (final practiceMirror in [true, false]) {
        final face = directionOf(
          practiceMirror: practiceMirror,
          platformPreviewBasis: FaceDirection.original,
        );
        expect(
          face.surfaceScaleX(SurfaceFace.cameraPreview),
          face.surfaceScaleX(SurfaceFace.clipPlayback),
          reason:
              '平台没镜像预览 ⇒ 两条练习路径的原始朝向相同 ⇒ 施加的缩放必相同'
              '（练习镜像=$practiceMirror）；「多出来那一次」是平台事实的函数，'
              '不是按路径硬编码的常量',
        );
      }
    });
  });

  group('跨面不变量：两条练习路径', () {
    const combinations = <(bool, FaceDirection, FaceDirection)>[
      (false, FaceDirection.original, FaceDirection.original),
      (true, FaceDirection.original, FaceDirection.original),
      (false, FaceDirection.mirrored, FaceDirection.original),
      (true, FaceDirection.mirrored, FaceDirection.original),
      (false, FaceDirection.original, FaceDirection.mirrored),
      (true, FaceDirection.original, FaceDirection.mirrored),
      (false, FaceDirection.mirrored, FaceDirection.mirrored),
      (true, FaceDirection.mirrored, FaceDirection.mirrored),
    ];

    test('① 切路径方向不变：同一开关取值下相机预览面与片段回放面方向相等', () {
      for (final (practiceMirror, previewBasis, saveBasis) in combinations) {
        final face = directionOf(
          practiceMirror: practiceMirror,
          platformPreviewBasis: previewBasis,
          platformSaveBasis: saveBasis,
        );
        expect(
          face.directionOf(SurfaceFace.clipPlayback),
          face.directionOf(SurfaceFace.cameraPreview),
          reason:
              '练习镜像=$practiceMirror 平台预览基准=$previewBasis '
              '平台保存基准=$saveBasis 下「录制所见 == 回看所见」',
        );
      }
    });

    test('② 开关两路一起翻：拨动练习镜像，两面的方向同时取反', () {
      for (final (_, previewBasis, saveBasis) in combinations) {
        for (final before in [false, true]) {
          final flipped = directionOf(
            practiceMirror: before,
            platformPreviewBasis: previewBasis,
            platformSaveBasis: saveBasis,
          );
          final after = directionOf(
            practiceMirror: !before,
            platformPreviewBasis: previewBasis,
            platformSaveBasis: saveBasis,
          );
          for (final face in [
            SurfaceFace.cameraPreview,
            SurfaceFace.clipPlayback,
          ]) {
            expect(
              after.directionOf(face).scaleX,
              -flipped.directionOf(face).scaleX,
              reason:
                  '练习镜像 $before → ${!before} 时 $face 的方向一起翻'
                  '（平台预览基准=$previewBasis 平台保存基准=$saveBasis）',
            );
          }
        }
      }
    });

    test('③ 锚定平台保存基准：它翻一次两路方向一起翻；'
        '平台预览基准不改方向、只改预览面的施加缩放', () {
      FaceDirection flip(FaceDirection d) =>
          d.isMirrored ? FaceDirection.original : FaceDirection.mirrored;

      for (final (practiceMirror, previewBasis, saveBasis) in combinations) {
        final face = directionOf(
          practiceMirror: practiceMirror,
          platformPreviewBasis: previewBasis,
          platformSaveBasis: saveBasis,
        );
        // 锚定关系不靠复述 ⊕ 表达：**平台保存基准**是两路方向的共同锚 ⇒ 它
        // 翻一次两路一起翻；两路彼此恒等（不变量①）也由这里再钉一次。
        final saveFlipped = directionOf(
          practiceMirror: practiceMirror,
          platformPreviewBasis: previewBasis,
          platformSaveBasis: flip(saveBasis),
        );
        expect(
          face.directionOf(SurfaceFace.cameraPreview),
          face.directionOf(SurfaceFace.clipPlayback),
          reason: '两路共用平台保存基准这一个锚（保存基准=$saveBasis 练习镜像=$practiceMirror）',
        );
        for (final which in [
          SurfaceFace.cameraPreview,
          SurfaceFace.clipPlayback,
        ]) {
          expect(
            saveFlipped.directionOf(which).scaleX,
            -face.directionOf(which).scaleX,
            reason: '平台保存基准翻一次 ⇒ $which 的方向随之翻（锚就是它）',
          );
        }

        // 平台预览基准是**预览面的自身原始朝向**，只补偿平台的预览镜像：
        // 它不动两路方向，只让预览面的施加缩放相对回放面多差一次。
        final previewFlipped = directionOf(
          practiceMirror: practiceMirror,
          platformPreviewBasis: flip(previewBasis),
          platformSaveBasis: saveBasis,
        );
        expect(
          previewFlipped.directionOf(SurfaceFace.cameraPreview),
          face.directionOf(SurfaceFace.cameraPreview),
          reason: '平台预览基准不进方向（它只在预览面的自身原始朝向里）',
        );
        expect(
          previewFlipped.surfaceScaleX(SurfaceFace.cameraPreview),
          -face.surfaceScaleX(SurfaceFace.cameraPreview),
          reason: '平台预览基准翻一次 ⇒ 预览面的施加缩放随之翻一次（补偿平台自拍镜像）',
        );
        expect(
          previewFlipped.surfaceScaleX(SurfaceFace.clipPlayback),
          face.surfaceScaleX(SurfaceFace.clipPlayback),
          reason: '平台预览基准不触及回放面的画面来源',
        );
      }
    });

    test('录制期冻结：武装那一刻取一次基线项，此后改它不动已冻结的素材方向，武装前改则取新值', () {
      // 武装：把那一刻的设备事实取成一份不可变值——录制会话持有它、此后只读
      // 同一实例（前言从武装那一刻开始写，故前言与正片同向）。
      const armed = SurfaceBaselines(
        platformPreviewBasis: FaceDirection.original,
        platformSaveBasis: FaceDirection.original,
      );
      // 武装前改（按下之后、武装之前）：这一次录制取的是新取的那一份。
      const armedLater = SurfaceBaselines(
        platformPreviewBasis: FaceDirection.original,
        platformSaveBasis: FaceDirection.mirrored,
      );
      // 武装后改基线项（设备事实变成「原相 ⊕ 镜像」）：拿在手里的那份冻结值
      // 一字不变（改的是新取的一份），而再武装一次会取到新值。
      expect(armed.materialDirection, FaceDirection.original);
      expect(armedLater.materialDirection, FaceDirection.mirrored);
      expect(
        momentFrom(armed).moment.baselines,
        armed,
        reason: '求值读的就是被冻结的那一份（同一份值）',
      );
      expect(
        momentFrom(armedLater).moment.baselines,
        armedLater,
        reason: '武装前改则取新值',
      );
    });

    test('录制期冻结：练习镜像是活的——同一份冻结基线项下拨开关两路当场翻', () {
      const armed = SurfaceBaselines(
        platformPreviewBasis: FaceDirection.original,
        platformSaveBasis: FaceDirection.original,
      );
      for (final before in [false, true]) {
        final flipped = momentFrom(armed, practiceMirror: before);
        final after = momentFrom(armed, practiceMirror: !before);
        for (final face in [
          SurfaceFace.cameraPreview,
          SurfaceFace.clipPlayback,
        ]) {
          expect(
            after.directionOf(face).scaleX,
            -flipped.directionOf(face).scaleX,
            reason: '练习镜像 $before → ${!before} 时 $face 当场翻（基线项冻结着）',
          );
        }
      }
      // 练习镜像不参与素材方向：活输入怎么拨都不动冻结的素材方向。
      for (final practiceMirror in [true, false]) {
        expect(
          momentFrom(
            armed,
            practiceMirror: practiceMirror,
          ).moment.baselines.materialDirection,
          FaceDirection.original,
        );
      }
    });
  });

  group('两个读法：方向与该面施加的缩放', () {
    test('源视频面施加的缩放 = 方向的符号（原相 +1 / 镜像 -1）', () {
      expect(directionOf().surfaceScaleX(SurfaceFace.sourceVideo), 1);
      expect(
        directionOf(globalMirrored: true)
            .surfaceScaleX(SurfaceFace.sourceVideo),
        -1,
      );
      expect(
        directionOf(
          fragments: const [LocalMirrorFragment(startMs: 0, endMs: 100)],
          positionMs: 50,
        ).surfaceScaleX(SurfaceFace.sourceVideo),
        -1,
      );
    });

    test('FaceDirection 两个取值与符号：原相 +1 / 镜像 -1', () {
      expect(FaceDirection.original.scaleX, 1);
      expect(FaceDirection.mirrored.scaleX, -1);
      expect(FaceDirection.original.isMirrored, isFalse);
      expect(FaceDirection.mirrored.isMirrored, isTrue);
    });
  });

  group('源视频面翻转闸门：上屏逐位置与渲染逐区间是同一份取值的两种读法', () {
    // 期望值独立写在这里（规格的真值表：全局镜像 ⊕（总开关 ∧ 落在半开区间内）），
    // 不由被测代码的另一个读法反算。
    const fragments = [
      LocalMirrorFragment(startMs: 1000, endMs: 2000),
      LocalMirrorFragment(startMs: 3000, endMs: 4000),
    ];

    test('逐位置读法：起点含、终点不含；总开关关时片段整组不参与', () {
      for (final globalMirrored in [true, false]) {
        for (final localMirrorEnabled in [true, false]) {
          final gate = SourceVideoFlip(
            globalMirrored: globalMirrored,
            localMirrorEnabled: localMirrorEnabled,
            fragments: fragments,
          );
          for (final (positionMs, covered) in [
            (0, false),
            (1000, true),
            (1999, true),
            (2000, false),
            (2500, false),
            (3000, true),
            (3999, true),
            (4000, false),
          ]) {
            final expectedLocal = localMirrorEnabled && covered;
            expect(
              gate.localActiveAt(positionMs),
              expectedLocal,
              reason:
                  '位置 $positionMs 的局部生效取值'
                  '（全局 $globalMirrored、总开关 $localMirrorEnabled）',
            );
            expect(
              gate.mirroredAt(positionMs),
              globalMirrored != expectedLocal,
              reason:
                  '位置 $positionMs 的翻转结果'
                  '（全局 $globalMirrored、总开关 $localMirrorEnabled）',
            );
          }
        }
      }
    });

    test('逐区间读法：生效窗就是片段表本身；总开关关时给空表', () {
      expect(
        const SourceVideoFlip(
          globalMirrored: true,
          localMirrorEnabled: true,
          fragments: fragments,
        ).localActiveWindows,
        fragments,
        reason: '窗不因全局镜像而变——全局那一枚是整片无窗的闸门',
      );
      expect(
        const SourceVideoFlip(
          globalMirrored: true,
          localMirrorEnabled: false,
          fragments: fragments,
        ).localActiveWindows,
        isEmpty,
        reason: '总开关关掉时片段整组不参与',
      );
    });

    test('上屏方向读同一份闸门：源视频面方向 = 闸门的逐位置翻转结果', () {
      for (final globalMirrored in [true, false]) {
        for (final positionMs in [0, 1000, 1500, 2000, 3000, 5000]) {
          expect(
            directionOf(
              globalMirrored: globalMirrored,
              fragments: fragments,
              positionMs: positionMs,
            ).directionOf(SurfaceFace.sourceVideo),
            SourceVideoFlip(
              globalMirrored: globalMirrored,
              localMirrorEnabled: true,
              fragments: fragments,
            ).directionAt(positionMs),
            reason: '位置 $positionMs 上面表与闸门必须同判（同一处声明）',
          );
        }
      }
    });
  });

  group('面表结构', () {
    test('五面齐全（源视频 / 相机预览 / 片段回放 / 录像文件 / 导出文件）', () {
      expect(
        SurfaceFace.values,
        containsAll([
          SurfaceFace.sourceVideo,
          SurfaceFace.cameraPreview,
          SurfaceFace.clipPlayback,
          SurfaceFace.recordingFile,
          SurfaceFace.exportFile,
        ]),
      );
      expect(SurfaceFace.values, hasLength(5));
    });

    test('未接线的面：读它们即报未实现（不静默取默认）', () {
      for (final face in [SurfaceFace.recordingFile, SurfaceFace.exportFile]) {
        expect(
          () => directionOf().directionOf(face),
          throwsUnimplementedError,
          reason: '$face 的取值表口径尚未接进面表',
        );
        expect(
          () => directionOf().surfaceScaleX(face),
          throwsUnimplementedError,
          reason: '$face 的缩放读法尚未接进面表',
        );
      }
    });
  });
}
