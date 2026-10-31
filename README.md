# Penna Comic（移植测试版）

基于 Penna 的 Windows 漫画工作台扩展。保留原项目 MIT 许可证；本版本与原版使用不同的数据目录。

## 已有功能

- 区域分镜、角色/画风文本卡、多页编辑。
- 通过已有 ComfyUI 生成整页图，串行批量、保存任务、续跑和单页重做。
- 中文对白由 Python 排字，成品预览及 CBZ/PDF 导出。
- 连接 OpenAI 兼容聊天服务。本地 Bonsai 的思考档位和上下文测量属于专门适配；其他模型能聊天，不保证这些扩展控件可用。
- TXT/EPUB 离线分章和规则分镜。小说工作区当前仅规划，尚未接通完整小说批量出图闭环。

## Windows 首次配置

需要 Windows 10/11 x64、已有 ComfyUI、已有 Python 3.10+ 和可用的聊天模型接口。

1. 完整解压发行ZIP，不要只复制 penna.exe。程序依赖同目录DLL和data资源。
2. 给选用的Python安装后端依赖：python -m pip install -r backend/requirements.txt。若使用ComfyUI已有Python，可先检查Pillow和psutil是否已装。
3. 在设置 → 漫画连接，选择真实Python可执行文件、设置ComfyUI地址和输出目录。工作流默认使用安装目录的 workflows/moss-api.json。
4. 点击“检查环境”。缺少MOSS支持、模型或节点时先解决提示；程序不自动下载模型或升级ComfyUI。
5. 在API管理添加自己的OpenAI兼容服务。需要本地模型时由用户预先启动。
6. 先用单页测试，确认文字框、LoRA和模型文件正确，再提交多页任务。

用户数据默认放在 %APPDATA%/PennaComic；不读取或迁移原版文档/Penna。可使用 PENNA_HOME 指定其他独立目录。
连接设置保存在该目录 integration.json；相对配置路径以它所在目录为基准。integration.example.json 只作格式示例，不会自动使用示例Python路径。
程序目录只含资源；任务/成品默认在用户目录的renders。不要把自己的数据目录放入公开仓库。

## 显存与模型管理

默认 external 模式：本程序不停止聊天服务、不卸载ComfyUI模型，也不替你配置显存。单卡显存不足时，先手动结束或卸载占显存的LLM，再出图；出图结束后手动启动LLM。

可选 managed 模式需在integration.json中明确配置 llama_executable、llama_model、完整 llama_args（字符串数组）、llm_url；只管理本程序启动且PID/创建时间/程序路径匹配的进程，不自动接管第三方已启动服务。它依赖NVIDIA nvidia-smi，默认启动前/后空闲显存门槛为13000/3072MiB，可用minimum_free_before_mib和minimum_free_after_mib调整。首次公开测试建议保持external模式。

## 工作流约定

仅支持随包提供的专用API图及保持接口约定的修改版，不接受任意ComfyUI图。关键节点ID：1基础模型、2采样配置、5正面、6负面、8采样器、11保存。
模板提供 MOSS UNET、Qwen文本编码器、VAE的示例文件名，须与本机模型列表一致。LoRA由面板选择替换模板LoRA链。默认不携带私人LoRA组合。

角色卡是文字提示约束，不是图像身份锁；跨页脸型、体型、服装仍可能漂移。最小工作流未做本次GPU画质验收，不承诺与原本机SLG工作流画质一致。

## 开发与构建

本次验证使用 Flutter 3.47.2 / Dart 3.13.2；锁文件随源码提供。完整Windows构建需要Visual Studio的C++桌面开发工具以及Flutter桌面插件所需链接支持。缺失时不要把本机旧DLL与新app.so拼接当成干净构建。

- flutter pub get
- dart analyze lib test
- 设置 PENNA_TEST_PYTHON 为测试用Python绝对路径后，flutter test --concurrency=2
- 在backend目录执行 python -m unittest discover -p "test_*.py" -q
- pwsh tool/build_windows.ps1 -Python python

GitHub Actions配置见 .github/workflows/windows.yml；它仅生成候选构建产物，不自动创建公开Release。
默认禁用原项目更新来源；确有自己的发行仓库时，构建参数 -UpdateRepo owner/repo 可启用对应源。上传前需验证发行包格式与更新路径兼容。
源码白名单打包：python tool/package_release.py source --out release/PennaComic-source.zip。
每包附逐文件SHA-256清单，另生成ZIP哈希文件。不要上传build目录、模型、用户配置、日志、作品、原文或测试私有数据。

## 发布状态

这是移植候选版，并非已完成跨机器验收的正式版。请先检查 docs/VALIDATION.md 的实际通过与未验证项。原项目与字体/依赖许可见 LICENSE、NOTICE.md 及 font目录许可证。源代码已上传至 https://github.com/sugdiy1/PennaComic （当前为私有仓库）；Windows候选包在Actions构建，未发布Release。
