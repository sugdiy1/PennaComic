import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/agent_control/control_runtime.dart';
import '../../../core/integration_settings.dart';

/// 显示可直接填入 DSH 的 stdio 命令；不显示本地访问令牌。
class ExternalAgentSection extends StatelessWidget {
  const ExternalAgentSection({super.key});
  @override
  Widget build(BuildContext context) {
    final runtime = ControlRuntime.current;
    final settings = IntegrationSettings.current;
    final actualHome = runtime.home ?? settings.home;
    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 32),
          const Text(
            '外部 Agent 控制（DSH / MCP）',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('打开后，本机 Agent 可以读取和修改分镜、提交出图任务与导出成品。每次启动默认关闭；内置聊天模型无需参与。'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('允许本机 Agent 控制 Penna'),
            subtitle: Text(
              runtime.changing
                  ? '正在切换…'
                  : runtime.running
                  ? '已启用 · 仅限本机连接'
                  : '已关闭',
            ),
            value: runtime.running,
            onChanged: runtime.changing ? null : runtime.setEnabled,
          ),
          if (runtime.error != null)
            Text(
              runtime.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (runtime.url != null) SelectableText('连接地址：${runtime.url}'),
          SelectableText('运行时数据目录：$actualHome（来源：${settings.homeSource}）'),
          if (runtime.savePath != null)
            SelectableText('分镜存档：${runtime.savePath}'),
          const SizedBox(height: 8),
          const Text(
            'DSH 添加 MCP → 本机命令（stdio），填写以下命令和参数。先在上方选择已有 Python 并保存配置。',
          ),
          const SizedBox(height: 8),
          SelectableText('命令：${settings.python}'),
          SelectableText(
            '参数（JSON 数组）：${jsonEncode(['${settings.bundleRoot}/backend/penna_mcp.py', '--home', actualHome])}',
          ),
          const SizedBox(height: 8),
          const Text(
            '连接后先让 DSH 调用 penna_status 和 penna_list_pages。修改页面前先读取版本号；penna_flush 可确认保存，penna_cancel_render 可取消出图，进度用 penna_get_task 查询。完整说明见随包 docs/DSH-MCP.md。',
          ),
        ],
      ),
    );
  }
}
