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
