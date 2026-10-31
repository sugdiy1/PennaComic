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
