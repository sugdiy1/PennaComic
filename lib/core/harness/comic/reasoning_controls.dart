import 'layout_context_policy.dart';
import 'local_chat_controls.dart';

/// 各服务的档位和请求协议不同，不能把 llama.cpp 参数发给云端。
enum ReasoningControl {
  unsupported,
  bonsai,
  deepseek;

  bool get supported => this != unsupported;
  List<String> get levels => this == deepseek
      ? const ['none', 'low', 'high', 'max']
      : const ['none', 'low', 'medium', 'high', 'xhigh'];

  String normalize(String level) {
    final value = level.trim().toLowerCase();
    if (levels.contains(value)) return value;
    if (this == deepseek) return 'high';
    return value == 'max' ? 'xhigh' : 'medium';
  }

  ReasoningPlan plan(String level) {
    if (!supported) return const ReasoningPlan();
    final value = normalize(level);
    if (this == deepseek) {
      return ReasoningPlan(
        enabled: value != 'none',
        effort: value == 'none' ? null : value,
        // 包含思考与正文；给结构化分镜保留足够的输出空间。
        maxOutputTokens: 32768,
      );
    }
    final local = bonsaiReasoningPlan(value);
    return ReasoningPlan(
      enabled: local.enabled,
      effort: local.effort,
      budgetTokens: local.budgetTokens,
      maxOutputTokens: local.maxOutputTokens,
    );
  }
}

ReasoningControl reasoningControlFor(
  String baseUrl,
  String model, {
  String protocol = 'openai',
}) {
  if (protocol != 'openai') return ReasoningControl.unsupported;
  if (isLocalBonsai(baseUrl, model)) return ReasoningControl.bonsai;
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri?.host.toLowerCase() == 'api.deepseek.com' &&
      const [
        'deepseek-flash',
        'deepseek-v4-pro',
      ].contains(model.trim().toLowerCase())) {
    return ReasoningControl.deepseek;
  }
  return ReasoningControl.unsupported;
}

class ReasoningPlan {
  const ReasoningPlan({
    this.enabled,
    this.effort,
    this.budgetTokens,
    this.maxOutputTokens,
  });
  final bool? enabled;
  final String? effort;
  final int? budgetTokens, maxOutputTokens;
}
