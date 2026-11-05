/// Read only the known MOSS API contract; never infer wiring for arbitrary graphs.
Map<String, dynamic> mossWorkflowDefaults(Map<String, dynamic> graph) {
  for (final entry in {
    '1': 'UNETLoader',
    '2': 'ModelSamplingAuraFlow',
    '5': 'CLIPTextEncode',
    '6': 'CLIPTextEncode',
    '7': 'EmptyFlux2LatentImage',
    '8': 'KSampler',
    '11': 'SaveImage',
  }.entries) {
    if (graph[entry.key] is! Map ||
        graph[entry.key]['class_type'] != entry.value) {
      throw const FormatException('请选择兼容的MOSS API工作流，界面格式或不同节点编号不能直接接力。');
    }
  }
  final reversed = <Map<String, Object>>[];
  final seen = <String>{};
  var link = graph['2']['inputs']['model'];
  while (link is List && link.length == 2 && link[0] != '1') {
    final id = '${link[0]}';
    if (!seen.add(id) ||
        graph[id] is! Map ||
        graph[id]['class_type'] != 'LoraLoaderModelOnly') {
      throw const FormatException('工作流LoRA链与当前接力接口不兼容。');
    }
    final inputs = graph[id]['inputs'] as Map;
    final name = inputs['lora_name'], strength = inputs['strength_model'];
    if (name is String && !name.contains('{{') && strength is num) {
      reversed.add({'name': name, 'strength': strength});
    }
    link = inputs['model'];
  }
  if (link is! List || link.length != 2 || link[0] != '1' || link[1] != 0) {
    throw const FormatException('LoRA链没有连接到基础模型。');
  }
  final sampler = graph['8']['inputs'] as Map;
  return {
    if (reversed.isNotEmpty) 'loras': reversed.reversed.toList(),
    for (final field in ['steps', 'cfg', 'seed'])
      if (sampler[field] is num) field: sampler[field],
  };
}
