# Susume — 为扒舞设计的舞蹈练习工具

Susume 是一个面向扒舞与日常练习场景的本地舞蹈工具。核心是针对练舞流程重新设计的视频播放器，支持分段与循环、节拍反馈、视频设置记忆、局部镜像、精细进度控制、倍速调节、对比回放，以及练习统计、计划管理和小组数据分享等功能。

## 能力

| | |
|---|---|
| **舞库** | 导入视频（内容指纹标识，重导入不丢标注）、卡片与详情、逐段熟练度、改名与删除、打开即续播 |
| **播放** | 帧级精确 seek、0.1–2.0 倍速（步长 0.05）、倍速步进、延迟播放、镜像（整片 / 局部片段）、音量亮度手势、三指跳转、长按 2× |
| **标注编辑** | 轨道带与控制层、分段线 / 半拍线 / 首尾边界、自动分段、八拍锚点、熟练度与重点、备注贴纸与点名、局部镜像片段、撤销重做、锁定分段、取景调节 |
| **节拍** | 节拍识别（原生 DSP + ONNX RNN + DBN 解码）、规整、节拍声（原生低延迟排程）、数拍与节拍动画、节拍对齐 / 八拍矫正 / 节拍倍频三条人工修正、音画同步校准 |
| **对比练习** | 前置摄像头与源视频分屏、录制、练习片段回看与截取、练习镜像、分屏取景 |
| **统计** | 练习场次与总时长、四拍桶明细、日历热力图、按舞排行、当前与最长连续天数 |
| **计划** | 舞 DDL、随舞事件、团内检查与达标门、复习提醒（本地通知）、日程与月视图 |
| **分享与备份** | `.susume` 单文件包（标注方案 + 可选媒体）、组员方案只读导入、整机备份与全量恢复 |

## 仓库结构

| 目录 | 内容 |
|---|---|
| `lib/core/` | 共享内核：播放引擎接缝与 media_kit 适配器、节拍网格接缝、当前拍求值、原子 JSON 文件 |
| `lib/player/` | 播放页与其各域模块：控制层、轨道带、标注编辑、节拍呈现、对比录制、取景、浮层、手势 |
| `lib/annotation/` | 标注纯域值类型与规则（零 Flutter 依赖） |
| `lib/persistence/` | 文档声明机制与落盘：公开标记文档、本地文档、组员方案、统计与四拍桶、计划、素材清单 |
| `lib/beat/` | 节拍识别管线（原生前处理 / DBN + ONNX 推理 + 规整） |
| `lib/beat_track_state/` | 节奏源：三态与可用性、时长基准 |
| `lib/dance/` | 舞库：合并读面与管理写路径 |
| `lib/home/` | 首页、舞详情、封面选帧、详细设置 |
| `lib/stats/` | 练舞统计读面与仪表盘 |
| `lib/plan/` | 计划页、日历事件、复习提醒与系统推送 |
| `lib/import/` | 视频导入管道 |
| `lib/package/` | `.susume` 包编解码、备份与恢复 |
| `lib/share/`、`lib/share_channel/` | 分享流程与平台分享通道 |
| `lib/camera_capture/` | 相机采集接缝与基准事实 |
| `lib/surface_direction/` | 画面方向：五个面共用一张表 |
| `lib/player_session/` | 播放会话模式 |

原生代码在 `android/app/src/main/cpp/`（节拍识别 DSP、AAudio 排程渲染器），经 `dart:ffi` 调用。

## 开发

> 本项目 100% 使用AI编写代码且未经仔细审核，可能存在很多愚蠢的写法（汗）
> 
> 本项目使用 mattpocock 工作流，安装 mattpocock/skills 以获得配套技能

### 环境

| | |
|---|---|
| Flutter | stable（本仓库在 3.47.2 / Dart 3.13.2 上开发） |
| JDK | 17 |
| Android SDK | NDK `28.2.13676358`、CMake `3.22.1`（`sdkmanager "ndk;28.2.13676358" "cmake;3.22.1"`） |

节拍识别的 DSP 与 AAudio 渲染器是真原生构建，缺 NDK / CMake 时 Android 侧编不出来。

### 构建与测试

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

`test/` 与 `lib/` 同构分目录，`test/helpers/` 放接缝替身与测试夹具。

正式签名读 `android/key.properties`（keystore 与凭据都不入库）；没有该文件时回落到 debug 签名。

`tool/` 下是离线工具：合成分拍夹具、跨发布版本夹具、相位探针。`tool/help_assets/` 由真机截图与录屏生成帮助条目资产，设备序列号经环境变量 `ADB_SERIAL` 传入。

## 文档

| | |
|---|---|
| `CONTEXT-MAP.md` | 上下文地图：本仓有哪几个上下文、各自住哪、彼此什么关系 |
| `lib/<主模块>/CONTEXT.md` | 该上下文的领域词表：概念的正名与避讳。术语以它为准 |
| `docs/adr/` | 系统级架构决策记录：做过什么决定、为什么 |
| `lib/<主模块>/docs/adr/` | 上下文级架构决策记录，编号与系统级连排 |
| `docs/agents/` | 代理工作流约定 |
| `NOTICE` | 第三方内容与许可说明 |
| `TRADEMARK.md` | 名称、应用图标与视觉识别的使用条件 |

## 许可

Susume © 2026 tideYurinka，以 [GNU General Public License v3.0](LICENSE) 发布。

`Susume` 名称、应用图标、logo 与官方视觉识别不在 GPL-3.0 授权范围内，使用条件见 [TRADEMARK.md](TRADEMARK.md)。

`assets/models/` 下的节拍识别模型来自 madmom 的预训练模型，受 CC BY-NC-SA 4.0 约束，不适用本仓库的 GPL-3.0，详见 [NOTICE](NOTICE)。

## 反馈

问题与建议请开 [issue](https://github.com/tideYurinka/Susume-DancePlayer/issues)。
