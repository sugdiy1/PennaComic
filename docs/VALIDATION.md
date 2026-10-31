# 移植候选版验证状态

2026-10-31。仅修改独立的 Penna-portable 源码，未替换正在使用的Penna安装或用户作品。

## 已验证

- Flutter完整回归及静态分析，最终结果见本次交付记录。
- Python后端回归，包括串行批次、断点续跑、选定LoRA链、未知占位符默认值、外部服务模式不停止模型、配置路径和打包排除私人数据。
- 独立中文/空格用户目录；UI保存ComfyUI连接配置后重新加载得到正确地址。
- 10项只读doctor检查（含随包中文字体），当前现有ComfyUI可读，基本节点和模型文件存在，没有提交生成。
- Dart release AOT及assets编译成功。这只验证Dart编译，不等于完整Windows安装包。

## 尚未通过或尚未执行

- 本机完整Windows构建被Flutter插件所需symlink支持阻止。未修改系统设置，未安装新的构建工具，未用旧安装的exe/DLL拼接成公开发行包。
- GitHub Actions已实际通过测试、完整Windows编译和ZIP上传。验证构建为cfe2845，运行记录：https://github.com/sugdiy1/PennaComic/actions/runs/41192057595 。
- 另一台机器/无E盘用户、真实GPU出图、最小工作流画质和多模型并存没有本轮实测。
- 角色一致性只是文本卡约束，不能承诺参考图锁脸。
- 字体许可已保留；其他上游图像和标签资产的独立来源仍待确认，见NOTICE。
- 已上传源代码到私有仓库 https://github.com/sugdiy1/PennaComic 。未发布Release。

## 依赖与复现

Flutter 3.47.2，Dart 3.13.2；pubspec.lock已随源码提供。后端本次使用Pillow12.1.0、psutil7.2.1，requirements-lock.txt固定了该验证组合。
设置PENNA_TEST_PYTHON为测试环境自己的Python绝对路径后运行flutter test。普通测试不读用户私有配置，不调用真实模型生成。上游本机专用探针和GPU测试未放入移植版普通回归。

## 更新策略

默认没有PENNA_UPDATE_REPO，返回无更新且不访问原项目更新API。上游更新复制的robocopy曾跳过大小/时间戳相同的文件，移植版加入/IS和/IT，既有真实临时文件回归已验证覆盖成功；复制失败时不继续删除缓存。


## 后续独立验证（2026-10-31）

- 源码候选包解压至全新的中文/空格目录，用单独创建的Python3.12.14虚拟环境安装requirements-lock.txt，49项后端测试通过。没有使用ComfyUI的Python来执行该次后端测试。
- 新增打包失败回归：疑似凭据阻止打包时不留下最终ZIP；拒绝含父目录/盘符/反斜线的归档条目及Windows大小写冲突。
- 499项Flutter回归和0项静态问题来自上一轮记录；本轮未改Dart逻辑，没有重复把同一批测试算作新增结果。
- 系统没有已注册的Visual Studio C++工具链；完整Windows安装包仍需GitHub Actions或具备工具链的干净Windows环境。
- GitHub连接器请求失败后，已通过Git现有HTTPS凭据上传至用户指定仓库；CI已实际运行。SSH未配置密钥，不关闭SSH主机验证。

## GitHub 构建排障

- 首次云端Flutter 499项通过；后端发现Windows临时目录长短路径表示差异，断言改为比较目录身份和文件名。
- 后续发现Skill保存测试依赖固定200毫秒等待；改为等待真实保存事件，未放宽功能断言。针对性9项测试通过，静态分析0问题。
- 中文排字优先使用随包字体；后端本地50项测试通过，10项只读环境检查通过。

## Windows 原生候选包验证

- 2026-10-31，GitHub Windows runner完整构建；499项Flutter测试、50项Python测试及静态分析通过。
- 最终ZIP SHA-256：53617b80ecae6da10c388c5b19a335629b7879c61951af9beb74fc09cbd6911b。56个文件逐项校验通过。
- 最终包在本机独立目录成功启动，版本1.1.0-comic.1；空白工作区，没有迁移用户作品。前一个相同Dart/后端版本另检查了漫画连接设置页，及独立Python下10项doctor全部通过。
- 本机缺少Windows构建工具的问题已通过云端完整构建解决；不是混合旧安装文件。
- 仍未完成另一台机器、无E盘环境或真实GPU出图验收。仓库仍私有，未发布Release。历史“本机构建受阻”保留为本机环境记录，不代表云端构建失败。
