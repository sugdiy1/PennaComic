import 'package:flutter/foundation.dart';

import 'control_server.dart';
import 'penna_tools.dart';

/// 仅由用户打开；每次启动默认关闭，不在后台自动开启控制入口。
class ControlRuntime extends ChangeNotifier {
  static final current = ControlRuntime();
  PennaTools? _tools;
  ControlServer? _server;
  bool changing = false;
  String? error;
  bool get available => _tools != null;
  bool get running => _server?.running ?? false;
  bool get busy => _tools?.busy ?? false;
  String? get url => _server?.url;
  String? get home => _tools?.home.path;
  void attach(PennaTools tools) {
    if (_server != null || changing) {
      throw StateError('Control runtime already attached');
    }
    _tools = tools;
  }

  Future<void> setEnabled(bool enabled) async {
    if (changing) return;
    changing = true;
    error = null;
    notifyListeners();
    try {
      if (enabled) {
        final tools = _tools;
        if (tools == null) throw StateError('控制入口尚未初始化');
        final server = _server ??= ControlServer(
          home: tools.home,
          listTools: () => tools.tools,
          callTool: tools.call,
        );
        await server.start();
      } else {
        await _server?.stop();
      }
    } on Object {
      error = '无法切换控制入口，请检查同一数据目录是否已有另一个实例。';
    } finally {
      changing = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _server?.stop();
  }
}
