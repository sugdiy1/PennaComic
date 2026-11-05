import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/ui/features/layout/workflow_binding_dialog.dart';

Map<String, dynamic> report({String? output}) => {
  'hash': 'test',
  'defaults': {'loras': []},
  'inspection': {
    'status': output == null ? 'needs_binding' : 'ready',
    'bindings': {'output': ?output, 'manage_loras': true},
    'outputs': [
      {'id': 'a', 'label': 'a · SaveImage'},
      {'id': 'b', 'label': 'b · SaveImage'},
    ],
    'samplers': [],
    'positives': [],
    'loras': [],
    'warnings': [],
    'errors': output == null ? ['请选择最终出图节点'] : [],
  },
};
void main() {
  testWidgets('歧义输出需选择，识别后允许保存，能切换保留原LoRA', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => WorkflowBindingDialog(
                  initial: report(),
                  inspect: (selection) async {
                    chosen = selection;
                    final next = report(output: selection['output'] as String?);
                    (next['inspection'] as Map)['bindings'] = selection;
                    return next;
                  },
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('b · SaveImage').last);
    await tester.pumpAndSettle();
    expect(chosen!['output'], 'b');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(chosen!['manage_loras'], isFalse);
    await tester.tap(find.text('保存绑定并导入参数'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkflowBindingDialog), findsNothing);
  });
}
