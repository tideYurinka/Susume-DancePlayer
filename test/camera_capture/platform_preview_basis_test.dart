import 'package:dance_learning_app/camera_capture/platform_preview_basis.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter_test/flutter_test.dart';

/// 平台预览基准 adapter 直测：把「相机实时预览件
/// 相对录像文件是否已被平台镜像」这件设备事实的取得分成两条路径——优先直接读
/// 相机引擎的 producer 标志；读不到按机型规则推导。两条路径都可注入，故两条
/// 都从这里驱动；推导不出时的兜底取值同样是显式分支，单独钉住。
///
///  的同帧取证订正了 Android 一行的取值：相机通路对前置实时预览做自拍
/// 镜像（插件 `ImageReaderRotatedPreview.frontFacingCamera` 分支在本机生效），
/// 实测预览件相对录像文件是镜像。
void main() {
  FaceDirection resolve({
    required CameraPlatform platform,
    required FaceDirection? producerFlag,
    FaceDirection? deviceBasisKey,
  }) => PlatformPreviewBasisAdapter(
    platform: platform,
    readProducerFlag: () => producerFlag,
  ).resolve(deviceBasisKey: deviceBasisKey);

  group('读取成功：相机引擎的 producer 标志', () {
    test('读到镜像 ⇒ 取镜像', () {
      expect(
        resolve(
          platform: CameraPlatform.android,
          producerFlag: FaceDirection.mirrored,
        ),
        FaceDirection.mirrored,
      );
    });

    test('读到的标志先于机型规则：规则无此平台也照读到的取值', () {
      expect(
        resolve(
          platform: CameraPlatform.other,
          producerFlag: FaceDirection.original,
        ),
        FaceDirection.original,
      );
    });
  });

  group('读取失败：按机型规则推导', () {
    test('Android 相机通路（前置、camera/CameraX）⇒ 镜像', () {
      expect(
        resolve(platform: CameraPlatform.android, producerFlag: null),
        FaceDirection.mirrored,
      );
    });

    test('规则表没有该平台 ⇒ 兜底为镜像，不是静默取默认', () {
      expect(
        resolve(platform: CameraPlatform.other, producerFlag: null),
        FaceDirection.mirrored,
      );
    });
  });

  group('设备级基准键：已落定的真机判据 / 人工覆盖优先于推导', () {
    test('键读得到 ⇒ 按它落定（两取值各一例）', () {
      expect(
        resolve(
          platform: CameraPlatform.other,
          producerFlag: null,
          deviceBasisKey: FaceDirection.original,
        ),
        FaceDirection.original,
      );
      expect(
        resolve(
          platform: CameraPlatform.other,
          producerFlag: null,
          deviceBasisKey: FaceDirection.mirrored,
        ),
        FaceDirection.mirrored,
      );
    });

    test('键先于机型规则推导：Android 规则为镜像也按键落定', () {
      expect(
        resolve(
          platform: CameraPlatform.android,
          producerFlag: null,
          deviceBasisKey: FaceDirection.original,
        ),
        FaceDirection.original,
      );
    });

    test('直接读到的 producer 标志先于键：读得到就不看键', () {
      expect(
        resolve(
          platform: CameraPlatform.android,
          producerFlag: FaceDirection.original,
          deviceBasisKey: FaceDirection.mirrored,
        ),
        FaceDirection.original,
      );
    });

    test('键缺失（null = 读不到）⇒ 回到推导链，不改判定', () {
      expect(
        resolve(
          platform: CameraPlatform.android,
          producerFlag: null,
          deviceBasisKey: null,
        ),
        FaceDirection.mirrored,
      );
    });
  });

  test('平台保存基准：CameraX 语义认定录像文件为原相', () {
    expect(platformSaveBasis, FaceDirection.original);
  });
}
