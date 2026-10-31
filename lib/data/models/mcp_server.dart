import 'package:flutter/foundation.dart';

const mcpHttp = 'http';
const mcpStdio = 'stdio';

String mcpTokenKey(String id) => 'mcp.$id.token';
String mcpEnvKey(String id) => 'mcp.$id.env';

/// 用户添加的一个 MCP 服务。令牌和环境变量是机密,存在 AppConfig.secrets 里。
@immutable
class McpServer {
  const McpServer({
    required this.id,
    required this.name,
    this.transport = mcpHttp,
    this.url = '',
    this.command = '',
    this.enabled = true,
  });

  factory McpServer.fromJson(Map<String, dynamic> j) => McpServer(
    id: j['id'] as String,
    name: j['name'] as String,
    transport: j['transport'] == mcpStdio ? mcpStdio : mcpHttp,
    url: j['url'] as String? ?? '',
    command: j['command'] as String? ?? '',
    enabled: j['enabled'] as bool? ?? true,
  );

  final String id;
  final String name;

  /// [mcpHttp](远程地址)或 [mcpStdio](在本机启动一个程序)。
  final String transport;
  final String url;

  /// 本机启动命令,整行,例如 `npx -y @scope/server`。
  final String command;
  final bool enabled;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'transport': transport,
    'url': url,
    'command': command,
    'enabled': enabled,
  };

  McpServer copyWith({
    String? name,
    String? transport,
    String? url,
    String? command,
    bool? enabled,
  }) => McpServer(
    id: id,
    name: name ?? this.name,
    transport: transport ?? this.transport,
    url: url ?? this.url,
    command: command ?? this.command,
    enabled: enabled ?? this.enabled,
  );
}
