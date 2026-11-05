import 'dart:io';

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
  String? get home => _tools?.home.absolute.path;
  String? get savePath => _tools?.vm.saveFile?.absolute.path;
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
    } on ControlException catch (e) {
      error = e.code == 'already_running'
          ? '数据目录已被其他控制实例占用：${home ?? "未初始化"}/control（${e.code}）'
          : '控制入口错误（${e.code}）：${e.message}';
    } on FileSystemException catch (e) {
      error =
          '文件系统错误（${e.osError?.errorCode ?? "未知"}）：${home ?? "未初始化"}/control。${e.osError?.message ?? e.message}';
    } on SocketException catch (e) {
      error =
          '本机端口启动失败（${e.osError?.errorCode ?? "未知"}）：${e.osError?.message ?? e.message}';
    } on StateError catch (e) {
      error = '控制模块未就绪：${e.message}';
    } on Object catch (e) {
      error = '控制入口启动失败（${e.runtimeType}），数据目录：${home ?? "未初始化"}';
    } finally {
      changing = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _server?.stop();
  }
}
