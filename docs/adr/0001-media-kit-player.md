# 播放器内核选用 media_kit

标注编辑要对参考视频做帧级精确寻址与区间循环回退，而 Android 上只能按关键帧粒度 seek 的内核撑不起数拍锚点与帧级预览。media_kit（mpv 内核）是五款候选里唯一开箱支持帧级精确 seek 的一款，`setRate` 覆盖任意倍速，内置字幕与叠加渲染，MIT 许可、全平台。

五款候选都没有区间循环，AB 与学习段循环因此在播放内核之上自建薄层：监听播放位置到 B 点后帧级 seek 回 A。

## Considered Options

- **video_player**：官方维护、许可宽松，但 Android 的关键帧 seek 是硬伤。
- **better_player / chewie**：继承同一寻址限制，且只支持预设倍速。
- **fijkplayer**：维护停滞。
