# GitHub 首次接入

建议仓库名：PennaComic；先设为私有，等构建验收后再公开。

1. 在你自己的GitHub账号新建一个空仓库，名称填PennaComic，选择Private；先不自动添加README、.gitignore或LICENSE，避免与已有文件冲突。
2. 将仓库链接发回本次开发对话，便于核对目标、上传独立源码并运行Windows candidate工作流。
3. 工作流目前只有读取仓库和上传构建产物权限，不自动建立Release，也不自动公开仓库。
4. 构建产物应包含完整exe、DLL、data、backend及workflow。先在另一台Windows机器配置外部ComfyUI和聊天接口，验收单页、多页、续跑、导出，再准备公开Release。

本地独立源码：Penna-portable目录。本机编译受Flutter链接支持及C++工具链限制；不要拿当前运行的Penna目录充当新版本发行包。源码候选ZIP不含Git凭据、用户数据或模型。

GitHub官方创建仓库文档：https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository
