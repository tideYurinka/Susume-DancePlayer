# import 域（导入管道）

选片 → 复制进应用私有目录 → 内容标识与索引 → 交给播放页。

## 选片与复制

- `VideoPicker` 抽象 + `SystemVideoPicker` 实现。file_picker v12 的破坏性 API 按 v12
  使用：`pickFile` 返回 `PlatformFile?`，取消为 null。
- `VideoImporter.copyToPrivateDir` 把所选文件复制到私有目录的 `videos/` 子目录，同名
  去冲突加 ` (n)` 后缀。源必须是 `file://` —— file_picker 会先把所选文件物化到自己
  的缓存目录，Android SAF 同样如此。
- 复制完成后调 `VideoPicker.clearCache()`（真实实现
  `FilePicker.clearTemporaryFiles()`）清掉选择器缓存。

## 视频标识与索引

- 主标识 = 内容 xxHash64（`XxHash64ContentHasher` 按块读取流式计算）；快速键 =
  大小 + 文件名（`fastKeyFor`）。
- `VideoIndexEntry` 带 videoId、显示名、文件路径、大小、快速键、镜像状态、最近打开
  时间；`VideoIndex` 负责快速键匹配与按 videoId 的 `upsert` 合并（保留镜像状态）
  / `refresh`；`VideoIndexStore` 读写 `index.json`，写链串行化防并发丢失。
- `VideoImporter.open` 快速键先行匹配：命中即立即播放既有私有副本，后台跑哈希校验
  （一致仅刷新最近打开时间；不一致按新视频导入、旧条目保留）；未命中走首次导入，
  复制后立即返回，哈希后台计算，不阻塞进入播放。

## 边界

只看文件侧：命名交互、节拍分析、播放编排都不在这里。视频标识为内容 xxHash64，见 `lib/core/video_identity.dart`。
