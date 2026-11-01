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
