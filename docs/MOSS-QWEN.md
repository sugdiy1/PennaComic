# MOSS 生成与 Qwen 2.1 修改

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
