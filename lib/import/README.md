# import 域（导入管道）

选片 → 边复制边算内容标识 → 索引落条目 → 交给播放页。

## 选片与复制

- `VideoPicker` 抽象 + `SystemVideoPicker` 实现。file_picker v12 的破坏性 API 按 v12
  使用：`pickFile` 返回 `PlatformFile?`，取消为 null。
- `VideoImporter.copyToPrivateDir` 把所选文件复制到私有目录的 `videos/` 子目录，同名
  去冲突加 ` (n)` 后缀。源必须是 `file://` —— file_picker 会先把所选文件物化到自己
  的缓存目录，Android SAF 同样如此。
- 复制与**内容标识**走同一遍流式读取：边写边喂 xxHash64，复制返回即指纹已知——指纹
  不再是复制之后的后台收尾，因此条目可以在返回播放页之前同步落盘。
- 复制完成后调 `VideoPicker.clearCache()`（真实实现
  `FilePicker.clearTemporaryFiles()`）清掉选择器缓存。

## 视频标识与索引

- 主标识 = 内容 xxHash64（`XxHash64ContentHasher` 按块读取流式计算，导入时与复制同
  一遍读取算出）；快速键 = 大小 + 文件名（`fastKeyFor`）。
- `VideoIndexEntry` 带 videoId、显示名、文件路径、大小、快速键、镜像状态、最近打开
  时间；`VideoIndex` 负责快速键匹配与按 videoId 的 `upsert` 合并（保留镜像状态）
  / `refresh`；`VideoIndexStore` 读写 `index.json`，写链串行化防并发丢失。
- `VideoImporter.open` 快速键先行匹配：命中即立即播放既有私有副本，后台跑哈希对账
  （一致仅刷新最近打开时间；不一致按新视频导入、旧条目保留）；未命中走首次导入，
  复制与指纹同步完成、条目**同步落盘**后返回。
- **打开一支舞不读视频内容**：打开恢复按 `filePath` 命中条目即取身份，不重算指纹
  （词条「视频标识」）。索引里查不到该路径的条目（索引写失败一类罕见情形）才兜底算
  一次，不留「无身份死局」。
- **副本丢失 → 找回**：`filePath` 不在盘上即「副本丢失」（词条见舞库），找回同样走
  本域——核对指纹一致后把副本复制回条目记录的原路径，于是路径不变量与按路径的那些
  写键一处都不用改。快速键命中而文件不在时按找回处理，不再只刷新显示信息。

## 边界

只看文件侧：命名交互、节拍分析、播放编排都不在这里。视频标识为内容 xxHash64，见 `lib/core/video_identity.dart`。
