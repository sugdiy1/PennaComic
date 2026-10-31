# 移植候选版验证状态

2026-10-31。仅修改独立的 Penna-portable 源码，未替换正在使用的Penna安装或用户作品。

## 已验证

- Flutter完整回归及静态分析，最终结果见本次交付记录。
- Python后端回归，包括串行批次、断点续跑、选定LoRA链、未知占位符默认值、外部服务模式不停止模型、配置路径和打包排除私人数据。
- 独立中文/空格用户目录；UI保存ComfyUI连接配置后重新加载得到正确地址。
- 9项只读doctor检查，当前现有ComfyUI可读，基本节点和模型文件存在，没有提交生成。
- Dart release AOT及assets编译成功。这只验证Dart编译，不等于完整Windows安装包。

## 尚未通过或尚未执行

- 本机完整Windows构建被Flutter插件所需symlink支持阻止。未修改系统设置，未安装新的构建工具，未用旧安装的exe/DLL拼接成公开发行包。
- GitHub Actions已提供，尚未在GitHub执行。完整Windows构建仍是公开二进制发布的门槛。
- 另一台机器/无E盘用户、真实GPU出图、最小工作流画质和多模型并存没有本轮实测。
- 角色一致性只是文本卡约束，不能承诺参考图锁脸。
- 字体许可已保留；其他上游图像和标签资产的独立来源仍待确认，见NOTICE。
- 没有创建远端仓库、上传源代码或发布Release。

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
- GitHub连接器暂时请求失败，远端仓库尚未建立、未上传源代码，CI仍未实际运行。
