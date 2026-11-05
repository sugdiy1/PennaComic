# MOSS 生成与 Qwen 2.1 修改

## 首次导入自己的工作流（comic.10）

1. 在 ComfyUI 导出 **API 格式 JSON**；普通界面 JSON（含 nodes/links/subgraphs）首版会明确提示重新导出，不会猜测转换。
2. 打开 Penna 的“一键接力”，点击 **导入 API 工作流**。程序从最终 SaveImage 反查 MOSS 采样器、正面条件和模型链；改过节点编号或标题都可以识别。
3. 检查“工作流识别与绑定”中的最终输出、采样器、正面入口，以及检测到的 LoRA、启用状态、模型/CLIP 强度。多个候选时下拉选择；不会修改负面提示词入口。
4. 点击 **保存绑定并导入参数**。LoRA 与采样默认值带入面板，后续面板设置可覆盖步数、CFG、种子和选定 LoRA；原采样算法、调度器、SLG 等节点保留。无固定 LoRA 的工作流会清空默认画风选择。
5. 绑定保存于个人数据目录 `workflow-bindings.json`，按文件路径与 SHA-256 匹配。再次打开可复用；文件内容改变后旧绑定失效，重新识别。出图前再次校验指纹，防止界面和实际文件不一致。

原生 `LoraLoaderModelOnly` / `LoraLoader`、rgthree `Power Lora Loader` 和 LoraManager 的固定文本列表支持读取。未知或动态管理器可关闭“由 Penna 管理 LoRA”，保留原工作流 LoRA；此时面板多选不会替换它们。缺少模型文件会提示准备文件，不自动下载或静默移除加速 LoRA。

首版支持 KSampler / KSamplerAdvanced 和可识别空白 latent 的 MOSS 文生图链路。特殊自定义采样器、动态图或图生图尺寸链可能需要另外适配；不会承诺所有魔改图都能自动识别。首次选定最终输出后只提交这条出图链的必要节点，避免顺带执行其他独立出图分支。原工作流文件不被改写。

## 官方 MOSS 采样链路兼容模板

可选工作流 `workflows/moss-official-api.json`，来源为 [Comfy-Org 官方 Layout 模板](https://github.com/Comfy-Org/workflow_templates/blob/main/templates/image_moss_image_t2i_bboxes.json)。这是适配 Penna 的 API 版，已展开子图、按接力后端要求调整编号，并使用本机已有的 int8 编码器与完整 Flux2 VAE。原生 shift 5 显式写为 AuraFlow 节点；保留官方 25 步、CFG 2.5、er_sde/simple、SLG 单层 22（0～0.5）。没有默认画风或加速 LoRA。Penna 提供已编译的 Layout 提示词，因此不需要官方画布编辑器或提示词增强分支。

在小说漫画设置或接力面板导入此 API JSON，确认**步数 25、CFG 2.5、取消加速 LoRA**，再出图。面板参数会覆盖模板默认值，不能沿用之前的 12 步/CFG 2 当作官方基准。选定画风 LoRA 属于额外变体，首次验证建议不选 LoRA。

本机 2026-11-03 实测，官方原生 Layout 链路在现有 16GB 显卡上完成 1024×1536 四格漫画，25 步约 42 秒（已缓存部分模型；冷启动会更慢）。多人动作、近景和四条中文对白可生成；手部与袖色仍需人工检查。模型写字，程序不重排台词。一次测试不能保证所有页面的文字和人物都正确。

## 逐格生成与精确拼接（comic.7）

出图模式选择「逐格生成并蒙版拼接」。当前页勾选真正的漫画格画框；人物、物件和文字框只是该格的内容，不要同时当作画框。自动识别优先选择名为「第1格」「第2格」等的最大对象框。多页接力按每页独立识别画框。

画框的矩形、椭圆或归一化多边形会成为实际合成蒙版。每格独立生成，台词由 MOSS 绘制，程序只拼图和画格边。可选每格再交给 Qwen 修改，仍须人工检查手部、人物一致性与文字。

点击画框旁的骰子再开始接力，会仅更换该格的种子；其他参数相同的格图直接复用缓存。改变整页风格、人物描述或全局种子可能使多格重新生成。中断后继续原任务会保留已完成格。

MCP 的 `render_mode` 为 `panels`；`panel_indices` 为当前页源 boxes 的零起始索引，`panel_seeds` 按该索引指定种子；多页模式请使用自动识别，不共享单页索引。

## 多页 Agent 与上下文（comic.7）

在区域控制聊天直接说「按这个故事生成15页漫画分镜」，程序会自动分成15次单页调用，不需要每页再说一次“继续”。每页写入成功才计入进度。遇到失败或点击停止会暂停，可点击「继续剩余页」。同系列新开聊天或重启软件后也可继续，重启不会自行发起模型请求。

原始任务、已完成页摘要和当前画布独立保存；聊天历史默认预算从12000字符提高到32000字符、最多24条，并移除重复的旧布局 JSON。字符预算不等于 token 上限，也不会提高 llama-server 的 `-c`。实际容量请以模型服务启动参数及上下文圆环读到的值为准。原始故事过长或持续加入大量附件，仍可能超过模型限制。

自动逐页执行解决任务过早结束与记忆丢失；不能保证小模型的剧情质量。需要稳定人物时请维护角色描述并逐页检查。

一键接力面板新增「出图模式」：

- **MOSS 生成**：沿用原有流程，台词与气泡由 MOSS 绘制。
- **MOSS 生成后由 Qwen 修改**：MOSS 分镜生成后，把原稿交给 Qwen 参考图编辑。支持当前单页与多页批量。
- **只修改已有图片（Qwen）**：选择与当前画布尺寸相同的 PNG，仅运行 Qwen。此模式使用当前单页，不加载 MOSS 模型。

「修改要求」可指定只修某一格、手部或遮挡，要求保留人物身份、服装、分格和台词。修改步数默认 25；Qwen 使用 CFG=1、euler/simple、denoise=1、resolution=0。宽高必须是 32 的倍数。

LoRA 面板只控制 MOSS 阶段，Qwen 不加载 MOSS LoRA。模型仍可能改变台词或画风，需要对照检查。没有程序排字。

## 配套模型

使用现有 ComfyUI，以下文件需要用户自行准备；软件不包含模型，不安装或更新节点：

| 目录 | 文件 |
| --- | --- |
| diffusion_models | qwen-image-2.1-UC-int8_convrot.safetensors |
| text_encoders | qwen3vl_8b_int8_convrot.safetensors |
| vae | qwen_image_2.1_vae_bf16.safetensors |

ComfyUI 需要原生 `TextEncodeQwenImage21`、`QwenImage21Cache` 节点。Qwen 缓存默认放 CPU，16GB 显卡依靠 ComfyUI 自动交换模型；建议先用 768×1024 测试。

连接设置中的工作流仍选择包内 **workflows/moss-api.json**，后端根据出图模式自动拼接 Qwen。不要把 ComfyUI 界面格式 JSON 填入 Penna 专用 API 模板设置。

## 输出与恢复

每个任务单独保存快照、参数和 manifest：

- `moss.png`：生成后修改模式的 MOSS 原稿；ComfyUI output 中也有原稿副本。
- `reference.png`：只修改模式的原始输入副本；任务创建后再改外部源文件不会影响这个快照。
- `raw.png` / `page.png`：最终输出；修改模式中为 Qwen 修改稿。
- `workflow.json`、`comfy-history.json`：实际提交图和执行记录。

失败后续跑复用已保存的 ComfyUI prompt_id，避免重复提交。终止按钮作用于当前接力任务，不清空其他任务。

## 来源

PennaComic 是基于 Penna 的衍生项目，原项目来源和许可证见 README、NOTICE 和 LICENSE。Qwen 接入使用 ComfyUI 原生参考图编辑节点，参数参考 [官方 Qwen 2.1 编辑模板](https://github.com/Comfy-Org/workflow_templates/blob/main/templates/image_qwen_image_2_1_image_edit.json)。模型文件来自 [第三方量化仓库](https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-Quantized)，其名称不构成质量保证；模型各自许可证单独适用。

## DSH / MCP 调用

`penna_submit_render` 的 settings 增加 `render_mode: "generate_edit"`、`edit_prompt`、`edit_steps`。省略 render_mode 沿用 MOSS 生成。单页或多页均可；本接口不接收外部图片路径，已有图片修改请使用软件单页面板。
