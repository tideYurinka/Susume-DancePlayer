# 投屏渲染路线关卡（#24）：在目标上量一次完整的 1080p 渲染

量测日期 2026-10-08。本关卡的唯一目的是回答一个问题：**投屏渲染走已链接的 ffmpeg
CLI（零新依赖），还是改 GPU 合成路线（Media3 Transformer）**。本文件是那次量测的
留档：入口、固定输入、读数、没读到的东西、结论与置信度。原始读数在同名目录下。

结论按 **claim → 证据 → 置信度** 组织。置信度取值：`confirmed`（实测直接读到）、
`inferred`（由一手证据合理推出）、`unconfirmed`（读不到，不猜）。

## 0 结论摘要

- **路线不变：继续用已链接的 ffmpeg CLI（`h264_mediacodec` 硬编），不引 Media3。**
  置信度 `inferred`——理由见 §8：换路线的触发条件是「连降到 720p 都到不了 1× 实时」，
  而**这条读数的宿主尚不存在**（见下一条），所以现在不换；同时 Media3 没有镜像效果
  这条**独立于吞吐**的理由本来就成立（ADR-0004 的 Considered Options）。
- **硬编那一档的真机读数**（1× 实时与否、编码器性能点）**本环境没取到**：这是一台
  只有**解码器**的 x86_64 模拟器，连软件 H.264 编码器都没有（§4.1）。要拿到它，把
  `tool/cast_render_bench.sh` 指向一台真机重跑即可（§9），命令、固定输入与判定都已就位。
- 规格里写死的**降级规则**（不足以 1× 实时 → 降 720p 并在准备面板明说）本轮**没有**
  被触发，也**没有**被证伪：它要的输入是真机硬编读数。

## 1 计时入口：一次跑出「墙钟 + 产物可播放性」

两个入口共用 `tool/cast_render_bench/bench_core.dart`（滤镜像与命令行、计时统计、
产物判定、性能读数解读全在这一个纯件里，纯 Dart 直测）——所以两侧读数可比。

```bash
# ① 宿主对照（本机 ffmpeg CLI，默认 libx264）：验证滤镜图与口径
dart run tool/cast_render_bench_host.dart --out /tmp/bench_host --runs 3

# ② 目标（真机或模拟器）：打包时只换入口（-t），不动任何生产文件
tool/cast_render_bench.sh -d <serial> --runs 3 --out /tmp/bench_device
#    默认 --encoder h264_mediacodec（本关卡要量的硬编那一档）
#    在没有硬编的目标上换包内软件编码器只为验滤镜图：--encoder mpeg4

# ③ 逃生口：只跑一条 ffmpeg 命令并把日志取回（迭代诊断，不必重打包）
tool/cast_render_bench.sh -d <serial> --no-build --exec /tmp/command.json
```

入口做的事：**固定输入**（缺失才生成）→ 编码器两问（`-h encoder=<名>` 能力输出、
带 debug 日志的组件名探针）→ **冒烟**（同一张图只出前一秒：链路上少一个滤镜或编码器
当场说话）→ 每档连跑 N 遍，每次只量**渲染那一次执行**的墙钟 → 每份产物做两处独立读数
（ffprobe：两路流/分辨率/时长；整片解码：错误与**帧数**）→ 汇总中位数、实时倍率、
分辨率影响系数。**退出码 0 不算出片**：产物判定与帧数判定说了算。

## 2 固定输入（同一串参数生成同一份输入）

30 秒、1920x1080、30fps、`testsrc2` 画面 + 440Hz 音轨；一张 480x162 的**半透明**
PNG 贴纸（alpha 恒 153）；一条 120bpm、880Hz、每拍开 60ms 闸的拍声。宿主生成后按字节
推给设备（推送后逐个核对字节数），哈希随读数留档：

| 输入 | 字节 | sha256 |
| --- | --- | --- |
| `source_1080p_30s.mp4` | 23038761 | `cf4cd34435edfff5fe56921dec1f2b641c633bf2d8be8a3b58cd076520a2ce1e` |
| `sticker_alpha.png` | 736 | `b50d0174e70e0cc16fc054da738b4295e43ed115dbecbe20e3623e6581bc6dff` |
| `beat_120bpm_30s.wav` | 5760078 | `44ef646f2c7ac11b9dae3d471dbb33684b9b48adb82af9d5a085ed63bfa83c34` |

渲染的那张图（`renderFilterGraph`，外部契约的一部分）：

```
[0:v]fps=30,format=yuv420p,hflip[g0];
[g0]hflip=enable='gte(t,2)*lt(t,4)+gte(t,10)*lt(t,12.5)'[g1];
[1:v]format=rgba,fps=30[stk];
[g1][stk]overlay=x=96:y=76:enable='gte(t,6)*lt(t,9)':format=rgb:eof_action=repeat[g2];
[g2]crop=1728:972:96:54,scale=<档位>,setsar=1,format=yuv420p[vout];
[0:a]aresample=48000[amain];
[2:a]aresample=48000,volume=0.6[abeat];
[amain][abeat]amix=inputs=2:duration=first:dropout_transition=0[aout]
```

编码参数显式给出（`-b:v 8M|4M -g 60 -r 30 -pix_fmt yuv420p -c:a aac -movflags +faststart`），
单帧贴纸输入不配 `-loop 1`、全命令不配 `-shortest`（靠 overlay 的 `eof_action=repeat`
铺满时间轴）。两档分辨率**只差末段 scale 与码率**——分辨率影响系数才有意义。

## 3 宿主对照（本机 ffmpeg CLI，libx264）

环境：Ubuntu 22.04，`ffmpeg 4.4.2-0ubuntu0.22.04.1`，24 核（`--encoder libx264`，
默认 preset）。三连跑：

| 档 | 三次墙钟 | 中位 | 实时倍率 | 产物 |
| --- | --- | --- | --- | --- |
| 1080p | 6223 / 6263 / 6418 ms | **6263 ms** | **4.79×** | 可播，900 帧，整片解码无错 |
| 720p | 5189 / 5210 / 5321 ms | **5210 ms** | **5.76×** | 可播，900 帧，整片解码无错 |

- **分辨率对耗时的影响系数（1080p 中位 ÷ 720p 中位）= 1.20**。置信度 `confirmed`。
- **只跑滤镜图（1080p，输出到 `null`，不编码）= 2824 ms**（约 10.6× 实时）：滤镜与
  合成**不是**这条链的瓶颈，编码占了大头。置信度 `confirmed`。
- 这是**宿主**读数，不是真机读数：它证明滤镜图成立、产物成立、口径可复算，**不**
  回答「手机硬编行不行」。

## 4 Android 目标上的读数

目标：`sdk_gphone64_x86_64`（Android 16 / API 36，`ro.hardware=ranchu`，x86_64，
google_apis 镜像），已链接包 `ffmpeg-kit-flutter-android-min-x86_64-8.0.0`，其
`ffmpeg n8.1.2` 自称有 `Encoder h264_mediacodec`（`-h encoder=h264_mediacodec` 能打出
帮助页，`General capabilities: … hardware`，像素格式 `mediacodec yuv420p nv12`）。

### 4.1 硬编那一档在本目标上**出不了片**（本关卡没能取得真机读数）

- **claim**：在这台目标上，`h264_mediacodec` 的渲染「返回码 0」，但**产物里一帧视频
  都没有**（只有音轨）。
- **证据**：`--exec` 跑最小命令（640x480、2 秒、`-loglevel verbose`）：

  ```
  Output #0, mp4, to '/data/user/0/top.yurinka.susume.debug/files/cast_bench/diag1.mp4':
    Stream #0:0: Video: h264, … (avc1 / 0x31637661) … q=2-31, 2000 kb/s, 30 fps
      Metadata: encoder : Lavc62.28.102 h264_mediacodec
  frame=    0 fps=0.0 q=0.0 Lsize=       0kB time=N/A bitrate=N/A speed=N/A
  video:0kB audio:0kB … muxing overhead: unknown
  ```

  完整滤镜图的 1 秒冒烟同样是 `frame= 0`、`video:0kB audio:12kB`，返回码 0
  （`android-emulator-h264-mediacodec-smoke.log`）。ffmpeg 的 mediacodec 封装在
  「编码器一个包都拿不到」时**静默成功**——这正是入口为什么要判产物、判帧数，而不是
  只看返回码。
- **原因（`inferred`）**：这台目标**根本没有 H.264 编码器**。`/vendor/lib64` 里只有
  解码器模块：

  ```
  libcodec2_goldfish_avcdec.so  libcodec2_goldfish_hevcdec.so
  libcodec2_goldfish_vp8dec.so  libcodec2_goldfish_vp9dec.so
  ```

  `/system/lib64` 里没有任何 `libcodec2_soft_*enc.so`；`service list` 里只有
  `…c2.IComponentStore/software` 一个组件库实例；`dumpsys media.codec` 这台目标上
  没有这个服务（见 `android-emulator-codec-supply.txt`）。**模拟器镜像不带编码器**是
  已知事实，不是本项目的配置问题。
- **置信度**：`confirmed`（读数为实测）。因此**「这台机器保不保证 1× 实时」这个问题
  在本环境里无从回答**：连编码器都没有，谈不上性能点。

### 4.2 换包内软件编码器，把滤镜图与流程在目标上跑完（`--encoder mpeg4`）

`mpeg4` 是已链接包自带的内部软件编码器（`-encoders` 实测在列）。换它**只为**在
「没有硬编的目标」上把整条链跑通、拿到可复算的读数；**它不是真机吞吐结论**。

| 档 | 三次墙钟 | 中位 | 实时倍率 | 产物 |
| --- | --- | --- | --- | --- |
| 1080p | 13900 / 13917 / 13989 ms | **13917 ms** | **2.16×** | 可播，**900 帧**，整片解码无错 |
| 720p | 10183 / 10102 / 10256 ms | **10183 ms** | **2.95×** | 可播，**900 帧**，整片解码无错 |

- **分辨率影响系数 = 1.37**；六次跑的中位数离散只有 0.9%（1080p）与 1.5%（720p）。
  置信度 `confirmed`（就这台目标、这个编码器而言）。
- 结论只能是：**「完整滤镜图 + 贴纸 + 混音 + 封装」这条链在 Android 目标上跑得通**，
  且产物可播、帧数一颗不少。真机硬编吞吐仍是缺口（§8）。
- **顺带一条与规格有关的实测**：同一张图里的 `-c:a aac` 在本包上**真能用**——冒烟日志
  里音轨是 `Audio: aac (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, … 192 kb/s`
  （`encoder : Lavc62.28.102 aac`），`audio:12kB` 就是它写出来的。规格指出
  `pubspec.yaml` 那句「min 变体只缺 libx264 与 AAC」是错的，本轮实测站在规格那一边。
  **但改那句话属于投屏渲染编排那张票**：本票明写「不动任何生产文件」，所以这里只留证据、
  不动 `pubspec.yaml`。置信度 `confirmed`。

## 5 镜像闸门：像素级验收（不只看命令跑没跑）

镜像闸门是本域最容易错的地方（全局镜像 ⊕ 时间窗局部镜像、半开区间 `[起,止)`），
所以宿主入口不只「跑通」，它按 PSNR 把产物与两份参考对照：**窗内应像未翻的原片、
窗外应像翻过的原片**（两个都开 = 净不翻）。参考帧与渲染共用同一段取景几何。

| 探针时刻 `t` | 像未翻的参考 | 像翻过的参考 | 应像哪一份 | 判定 |
| --- | --- | --- | --- | --- |
| 1.0 s（窗外） | 5.85 dB | **45.69 dB** | 翻过 | ✅ |
| 2.0 s（窗 2–4 的**起点**） | **45.40 dB** | 5.87 dB | 未翻 | ✅ |
| 3.0 s（窗内） | **44.53 dB** | 5.89 dB | 未翻 | ✅ |
| 4.0 s（窗 2–4 的**终点**） | 5.89 dB | **44.67 dB** | 翻过 | ✅ |

- claim：`hflip` 的时间窗写法（`enable='gte(t,起)*lt(t,止)'`）与半开区间口径在**像素上**
  成立：起点那一帧算窗内、终点那一帧算窗外。置信度 `confirmed`。
- claim：这条链上 `overlay` 的全分辨率 alpha（`format=rgba` 输入 + `overlay:format=rgb`）
  与取景裁切缩放都在产物里生效。置信度 `confirmed`（贴纸窗口与取景都在图上；alpha 的
  生成与读回在入口里单独核对：alpha 区间 153..153、不是不透明的 255）。

## 6 编码器性能点：读到了什么、没读到什么

- **读到**：`-h encoder=h264_mediacodec` 的能力输出（`found=true`，`name=h264_mediacodec`，
  `General capabilities: dr1 delay hardware`，像素格式 `mediacodec yuv420p nv12`）；
  组件名探针的完整日志；本目标的编解码器供给（§4.1）；以及**实测吞吐**本身。
- **没读到**：Android 的**编码器性能点**（`MediaCodecInfo.VideoCapabilities
  .getSupportedPerformancePoints()`，API 29+）是 Java 侧 API，只有经平台通道才能拿。
  本入口**不改任何生产文件**（`MainActivity`、`AndroidManifest.xml`、`pubspec.yaml` 都不动），
  所以没有通道可用；`dumpsys media.codec` 这条命令行退路在这台目标上也没有这个服务。
  真机上的退路是：`tool/cast_render_bench.sh` 会把 `dumpsys media.codec` 的尝试与
  `service list` 一起写进 `device_env.txt`；而**性能点的正式查询属于生产路径**，
  它要等投屏渲染编排那几张票落地时经平台通道问（规格里写死的降级判据就是它）。
- 因此「这台机器保不保证 1× 实时」的**正式答案**在本轮**没有产出**；能产出的替代证据
  只有上面那些能力输出与本目标的实测吞吐。置信度：`unconfirmed`（性能点）、
  `confirmed`（替代证据）。

## 7 热与降频观察（连跑三次）

- 目标侧（模拟器）：跑前跑中 `dumpsys thermalservice` **Thermal Status 0**（无节制），
  `battery 25.0°C`、`skin 30.1–30.2°C`，全程几乎不动；`dumpsys battery` 的
  `temperature: 250`（0.1°C 单位）也一路不变。
- 宿主侧（真正在算的是宿主 CPU）：`thermal_zone*` 在 46–77°C 之间浮动，
  `nvidia-smi` 47°C / 210 MHz（本轮不涉 GPU 编码）。
- **降频迹象**：没有。六次跑里 1080p 的离散是 13900–13989 ms、720p 是 10102–10256 ms，
  第 3 跑既没有变慢也没有变快（`android-emulator-mpeg4-thermals.log` 与读数表）。
  置信度 `confirmed`（就这台目标而言）。

## 8 结论与缺口

1. **路线结论：继续用已链接的 ffmpeg CLI（`h264_mediacodec`），不引 Media3。**
   - 硬编那一档的真机读数**还没拿到**（§4.1、§6），所以这条结论**不是**「吞吐实测过关」
     得出的；
   - 它站得住的两条腿是：**(a)** Media3 **没有镜像效果**，时间窗还得靠
     `TextureOverlay` 子类自写——换路线不是等价替换，是把 ffmpeg 已经白送的东西重造一遍
     （ADR-0004 的既有理由，与本轮读数无关）；**(b)** 本轮在目标上把**完整滤镜图**跑通、
     产物可播、帧数齐、镜像闸门在像素上成立，说明这条链在 Android 侧没有硬伤，
     吞吐风险有规格里写死的**降级梯子**（不足 1× → 720p）兜着。
   - 置信度 `inferred`。
2. **缺口（需要一台真机才能关掉）**：在真机上跑
   `tool/cast_render_bench.sh -d <真机 serial> --runs 3`，读 `h264_mediacodec` 的
   1080p / 720p 中位墙钟与帧数。它同时回答「1× 实时」与「分辨率影响系数」。
3. **换路线的触发条件（写死，免得将来靠印象）**：真机读数显示 **1080p 与降到 720p 都
   到不了 1× 实时**（中位墙钟 > 素材时长），才动 GPU 合成路线；那时**另开一条 ADR**，
   **不改写 ADR-0004**（ADR-0004 已写明 Media3 是「吞吐不过关时的退路」）。
4. **本轮没有触发降级**：模拟器上软编 1080p 是 2.16×、720p 是 2.95×，两档都在实时之上；
   但这不是硬编读数，**不能**用它给真机下结论。
5. **入口本身也交出一个教训**（已写进入口的判定）：第一次在目标上跑，六次渲染**返回码
   全是 0**，产物却只有音轨（6 份文件字节数完全相同，343260 字节）。是「ffprobe 读流 +
   整片解码数帧」两处独立读数把它揪出来的——所以**产物可播放性**不是「返回码 0」，
   是「两路流齐、分辨率对、时长对、字面帧数一颗不少」。

## 9 复跑与留档文件

```bash
dart run tool/cast_render_bench_host.dart --out /tmp/bench_host --runs 3
tool/cast_render_bench.sh -d <serial> --runs 3 --out /tmp/bench_device
```

同目录下的原始读数（都是入口直接写出的 JSON，未经改写）：

| 文件 | 是什么 |
| --- | --- |
| `host-libx264.json` | 宿主对照：三连跑、只跑滤镜图、镜像闸门的 PSNR 探针、输入哈希 |
| `android-emulator-mpeg4.json` | 目标上（软编 mpeg4）三连跑的全部读数与判定 |
| `android-emulator-mpeg4-thermals.log` | 同一轮每 15 秒一次的热采样（目标 + 宿主） |
| `android-emulator-h264-mediacodec.json` | 硬编那一档在本目标上的失败留档（冒烟未出片） |
| `android-emulator-h264-mediacodec-smoke.log` | 上面那次的 1 秒冒烟完整日志（verbose） |
| `android-emulator-codec-supply.txt` | 本目标的编解码器供给（服务、模块、`dumpsys`） |
| `android-emulator-env.txt` | 目标环境快照（机型、ABI、系统、编解码器服务） |

**原生与真机行为留真机验收**：本文件里所有「目标」读数都来自一台 x86_64 模拟器，
它的编码器供给与真机不同（§4.1）。真机那一次的读数应当追加到本目录，而不是覆盖。
