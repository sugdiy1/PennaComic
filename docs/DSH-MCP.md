# 用 DSH 控制 Penna

Penna 的 MCP 桥接器让 DSH 读取页面、修改分镜、提交渲染和导出漫画。桥接器只需要 Python 3.10 或更新版本的标准库，无需安装 Python 包。

## 连接步骤

1. 打开支持代理控制的 Penna，在设置的「漫画连接」中开启代理控制。保持 Penna 运行。
2. 确认 Penna 使用的数据目录，即 `PENNA_HOME`。未自定义时通常为 `%APPDATA%\PennaComic`；以 Penna 当前显示的连接信息为准。`--home` 指向数据目录，不是安装目录。
3. 在 DSH 的 MCP 设置中新增 **stdio** 服务，命令填写 Python 可执行文件的绝对路径，参数依次填写桥接脚本绝对路径、`--home`、数据目录绝对路径。可直接使用 Penna 设置提供的命令和参数。
4. 保存后让 DSH 重新连接该服务，确认工具列表中出现 `penna_status` 等工具。

下面是通用 MCP 配置示例。示例路径需要替换为你的实际路径；它不是 DSH 配置文件位置或磁盘格式的声明。如果 DSH 提供 JSON 导入，可按其界面要求导入；如果它提供独立的命令和参数栏，分别填入 `command` 和 `args`。

```json
{
  "mcpServers": {
    "penna": {
      "command": "C:\\Python312\\python.exe",
      "args": [
        "C:\\Penna\\backend\\penna_mcp.py",
        "--home",
        "C:\\PennaData"
      ]
    }
  }
}
```

不要在 stdio 服务参数中加入 `--check`。桥接器运行时保持等待 DSH 的消息是正常现象；它不会自行打开 Penna。

## 先检查连接

可以在 PowerShell 中执行一次只读检查：

```powershell
& 'C:\Python312\python.exe' 'C:\Penna\backend\penna_mcp.py' --home 'C:\PennaData' --check
```

成功时显示 `Connected to Penna: … tools available.`，并以 0 退出。检查只读取连接信息和工具列表，不编辑页面、不启动渲染。失败时先确认 Penna 已打开、代理控制已开启、`--home` 与 Penna 的数据目录一致。不要手动固定端口或把令牌复制进 DSH 配置。

## 可以对 DSH 这样说

- “连接 Penna，列出当前工作区的系列和页面，并告诉我第 1 系列第 2 页的分镜内容。”
- “读取第 1 系列第 2 页，把第二格的提示词改成雨夜街头，其他内容保持原样。完成后重新读取确认。”
- “为刚才确认的页面提交渲染，把任务编号告诉我，然后查询任务，完成后列出结果。”
- “查看现有结果，并用 Penna 的导出工具导出漫画。”

工具的准确参数以 DSH 获取的工具描述为准。页面由整数 `series` 和从 1 开始的 `page_number` 标识。编辑现有页面时，先调用 `penna_get_page`，取得完整页面和 `revision`；调用 `penna_update_page` 时把这个值作为 `expected_revision`。布局沿用读取结果中的 Penna `Layout.toJson` 结构。

若提示版本冲突，重新读取页面并结合最新内容修改，不要重复提交旧版本。渲染提交会快速返回任务编号，使用 `penna_get_task` 查询；不要为了等结果而重复提交同一渲染。Penna 正在内置对话生成时可能拒绝页面修改，等对话完成后重新读取再操作。没有删除页面工具。可用 penna_flush 显式确认分镜保存，用 penna_cancel_render(task_id) 取消本工具提交的任务。

## 连接范围

控制服务默认关闭，只监听本机 `127.0.0.1`，使用临时随机端口和令牌。桥接器从 `<home>\control\connection.json` 获取连接，每次请求重新读取，因此 Penna 重启后无需手改端口。关闭代理控制或退出 Penna 后连接失效。不要分享连接文件或令牌。

桥接器拒绝非字面量 IPv4 回环地址、重定向和代理转发，不提供任意命令执行或任意文件读取接口。它只在标准输出中写入 MCP 消息。`--check` 则输出供人阅读的检查结果，不能作为 DSH 的服务启动模式。

支持换行分隔的 JSON-RPC MCP stdio，包括 `initialize`、`ping`、`tools/list`、`tools/call` 和通知。支持协商 `2024-11-05`、`2025-03-26`、`2025-06-18`、`2025-11-25`；未知版本返回桥接器支持的最新版本供客户端判断。页面冲突等业务错误通过工具结果的 `isError` 和文本中的 JSON 错误返回。

## 开发验证

在源码根目录运行：

```powershell
python backend/test_penna_mcp.py -v
```

测试使用临时数据目录、真实桥接器子进程和本机假的 HTTP 服务，不读取真实作品，也不调用 GPU。它验证 MCP 与 HTTP 转发行为；DSH 实际界面的兼容性和真实渲染需要在目标环境另行验证。

## 任务与窗口生命周期

关闭“外部 Agent 控制”只断开连接，不取消已经提交的出图。出图期间请保持 Penna 运行，等 penna_get_task 返回 done 或 error 后再退出。可调用 penna_cancel_render(task_id) 发出取消请求；先返回cancelling，待penna_get_task确认cancelled后再退出。只停止该任务后续提交，删除它自己的待执行prompt，按prompt_id中断它自己的运行任务；不清空他人队列。不要通过结束进程来取消正在占用GPU的任务。

若 Penna 意外退出，下次启动会将未确认完成的控制任务标记为 interrupted。重新连接后先查成品/任务状态，按相同页面和参数重新提交可查找已保存批次续跑；已完成页由后端校验后跳过。不能承诺退出后的后端一定继续完成。

新建页会追加到指定系列，保留当前选中页。已有空白第1页不会自动被覆盖；要使用空白页，先 get_page 再 update_page。画布尺寸上限遵循 Penna 自身限制：64–4096 像素。

## 常用工具

| 工具 | 用途 |
|---|---|
| penna_status | 当前工作区、内置Agent状态、出图任务 |
| penna_list_pages / penna_get_page | 页面列表、完整布局和版本号 |
| penna_create_page / penna_update_page | 新增或修改指定页；角色卡位于layout.cast |
| penna_list_loras | 读取本机ComfyUI可用LoRA |
| penna_submit_render / penna_get_task | 单页/多页出图，查询阶段和结果 |
| penna_list_results | 查看当前稿及旧稿的成品路径 |
| penna_export_comic | 按页码导出当前稿成品CBZ/PDF到配置输出目录的exports子目录 |

## 斜切、多边形和椭圆

不能根据当前页面的字段并集判断全部可用字段。矩形框不包含可选shape字段，Penna原有数据层仍支持它。控制接口使用内部Layout格式：box是画布整数像素外框，shape多边形是相对这个外框的0–1归一化顶点。不要与旧聊天草稿的画布像素shape坐标混用。

以下是一个左上角斜切的画格，shape按顺序连接并闭合：

```json
{
  "box": [40, 40, 790, 560],
  "label": "object",
  "name": "第1格",
  "caption": "Comic panel with a diagonal top edge rising from left to right; an adult courier enters the station.",
  "shape": [[0, 0.15], [1, 0], [1, 1], [0, 1]],
  "layer": "middle",
  "text": ""
}
```

`shape: "ellipse"` 是椭圆，`shape: "rect"` 或null恢复矩形；矩形读取结果通常省略shape。多边形支持3–16个顶点，每点恰好两个有限数值，范围0–1。修改其他字段时保留已存在的shape。

shape目前保证画板显示、MCP读写与存档，不保证整页MOSS成品的精确裁切。MOSS只收到外框bbox和描述，必须在caption中说明斜边、圆形等轮廓。严格的多边形蒙版仍需逐格生成后程序合成；现有小说compositor的预设斜切能力尚未接到这个MCP整页出图入口。出血构图可以将box贴到画布边缘，但没有单独的精确出血/无边框控制字段。

## 数据目录、存档与诊断（1.1.0-comic.4）

桌面程序和MCP都支持 `--home <绝对目录>`。桌面目录优先级为命令行--home、PENNA_HOME环境变量、APPDATA/PennaComic默认值。设置页会显示实际运行目录及分镜存档位置；MCP的--home必须与它一致。控制服务默认关闭，connection.json仅在成功开启期间存在，关闭后删除；不要删除运行实例的server.lock来尝试解锁。锁文件存在本身不代表被占用。

分镜工作台的分页存档为layout_chat.json；workspace.json是另一个提示词成稿工作区。create/update已自动原子落盘，penna_flush是额外的保存确认，成功返回实际save_path和page_count。不要将两个存档互相覆盖。

layout.json会在启动时读取，随后区域工作台会载入layout_chat.json中选中的页。空白旧存档可收纳layout.json，但已有页面优先，不会因为外部改了layout.json就覆盖当前分镜。需要修改已有页请通过MCP或界面导入。

连接失败时请查看设置页具体错误：文件系统错误含数据目录和系统错误码；锁占用与端口失败分别显示，不再统一归因为另一个实例。penna_status还会返回home和save_path供Agent核对。

渲染取消依赖ComfyUI对prompt_id定向interrupt的支持。本机0.43.1已核对实现支持；本程序不发送无prompt_id的全局interrupt，也不发送全局清队列。取消后显存恢复仍需等待ComfyUI队列空闲。
