# 1.1.0-comic.10

- 修复官方 DeepSeek API 连接下思考菜单灰色不可用：deepseek-flash / deepseek-v4-pro 显示关闭、低、高、最高四档。
- 使用官方 thinking.type 与 reasoning_effort 参数，关闭时不发送 reasoning_effort；不会发送 llama.cpp 模板或本机预算参数。
- 区域控制聊天、小说资产准备、逐页分镜及 JSON 纠错均继承思考设置。旧中档/极高档按官方规则映射到高，最高档 max 可保存。
- 本地 Bonsai 保留原五档；其他尚未适配的接口继续显示明确提示。
- 新增 MOSS 官方采样链路的 Penna API 兼容模板（25 步、CFG 2.5、er_sde/simple、SLG22），与既有加速模板并列提供。
- 首次导入 API 工作流按连接关系识别正面提示词、采样器、尺寸、最终输出与 LoRA，不再限制固定节点编号。多候选支持手动绑定，绑定按文件指纹保存；内容变化后重新检查。
- 支持原生 LoRA、rgthree Power LoRA 与 LoraManager 文本列表；不支持的管理器可保留原链路。CLIP 强度独立保留，未启用条目不默认勾选。

# 1.1.0-comic.9

- 小说资产与分镜统一处理AI答复：仅移除字符串外的尾逗号，保持台词内容不变。
- JSON语法错误自动纠错重试一次，保留原始任务；仍失败时给出可恢复的提示，不无限重试。
- 布局编号、格数和资产字段继续严格校验，不猜测补造剧情或缺失字段。

# 1.1.0-comic.8

- 小说漫画接入已有AI连接，先准备可编辑的文字角色/场景/道具资产，再逐页设计分镜。
- 内置121套实际几何布局，AI按剧情匹配，展示文字备选与选择理由；不把文字方案当作视觉验收。
- 增加暂停续做、单页AI重设计、文字卡保留与别名归并，小说页面可进入既有接力和成品导出。
- 接力面板开放MOSS CFG，支持填写并实际提交CFG 2等参数。
- 提供“自行复制提示词 / 用我的工作流出图”二选一；支持整页/逐格提示词与台词导出，兼容MOSS API工作流的参数注入和默认LoRA读取。

# 1.1.0-comic.7

- 一次要求生成多页分镜时自动逐页执行，保存原始要求、页面摘要和进度，暂停后可继续剩余页。
- 区域控制对话使用当前画布事实与较长的有界历史；避免旧布局 JSON 挤占上下文。模型服务自身的上下文上限保持其配置。
- 新增逐格生成并蒙版拼接：矩形、斜切多边形、椭圆按真实画框合成，支持单格换种子及缓存复用。
- 逐格台词仍由模型绘制；成品预览与导出过滤中间格图。

# 1.1.0-comic.6

- 一键接力增加 MOSS 生成、生成后由 Qwen 修改、只修改已有图片三种模式。
- 支持填写修改要求、独立修改步数、原稿保留及批量生成后修改。
- 修改模式明确读取最终输出节点，避免误将原稿作为修改稿。
- 沿用专属任务取消和断点续跑，不包含模型与用户作品。

# 1.1.0-comic.5 (candidate)

- New relay jobs send dialogue and text regions directly to MOSS; no programmatic lettering or text suppression.
- Removed the bubble-style selector. Added a cooperative stop button in the render panel.
- Legacy saved jobs retain their original composition behavior for resume compatibility.

# 1.1.0-comic.4 (candidate)

- Desktop --home now selects the actual data directory, ahead of PENNA_HOME and APPDATA defaults.
- Display runtime home/archive and distinct filesystem, lock and socket diagnostics; failed control startup remains retryable.
- Added penna_flush durability confirmation and penna_cancel_render cooperative task cancellation.
- Cancel stops later submissions, preserves completed pages, targets only owned ComfyUI prompts and protects resumability before submission.
- Clarified layout_chat.json versus workspace.json and startup board/page precedence.

# 1.1.0-comic.3 (candidate)

- Exposed optional shape in MCP layout schemas: normalized polygon vertices, ellipse and rectangle reset.
- Added strict shape validation instead of silently clamping/dropping malformed geometry.
- Verified polygon round trips through control create/read/update, live board and saved reload.
- Documented that whole-page MOSS generation does not provide exact polygon masks; precise per-panel composition remains a separate path.

# 1.1.0-comic.2 (candidate)

- Added opt-in local control API and Python stdio MCP bridge for DSH.
- External agents can read/create/update specific pages, select LoRA, submit sequential render batches, poll tasks, list saved results and export CBZ/PDF.
- Page revisions reject stale edits. External writes update live UI and persist atomically; failed writes restore live review state.
- Control defaults off on each launch, binds loopback with a fresh bearer token, and exposes no arbitrary shell or file-reading tool.
- See docs/DSH-MCP.md for setup and task lifecycle limitations. Original Penna attribution and MIT license retained.

# 1.1.0-comic.1 (candidate)

- Integrated comic relay, sequential batches, composition, export and offline novel planning backends.
- Added connection settings and read-only environment checks.
- Removed machine-specific installation paths; isolated user data in PennaComic.
- External service mode is the default and does not unload or terminate models.
- Disabled upstream automatic updates unless a fork update repository is set at build time.
- Added whitelist packaging and Windows CI build instructions.

This is a development candidate. Cross-machine GPU rendering, the minimal
workflow and the GitHub Actions build require independent acceptance before a public release.

- Packaging now stages output atomically and rejects unsafe or case-colliding ZIP entry paths. Clean Python 3.12 extraction regression: 49 tests passed.
