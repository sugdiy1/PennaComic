import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// A public, safe-to-display failure from a control tool.
class ControlException implements Exception {
  final String code;
  final String message;

  const ControlException(this.code, this.message);
}

/// Opt-in, authenticated control transport for the live application.
class ControlServer {
  final Directory home;
  final List<Map<String, Object?>> Function() listTools;
  final Future<Map<String, Object?>> Function(String, Map<String, dynamic>)
  callTool;

  HttpServer? _server;
  RandomAccessFile? _lock;
  String? _token;
  Future<void> _dispatch = Future<void>.value();
  Future<void> _lifecycle = Future<void>.value();

  ControlServer({
    required this.home,
    required this.listTools,
    required this.callTool,
  });

  bool get running => _server != null;
  String? get url =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}';
  String get discoveryPath => p.join(home.path, 'control', 'connection.json');

  Future<void> start() => _sequence(_start);
  Future<void> stop() => _sequence(_stop);

  Future<void> _sequence(Future<void> Function() operation) {
    final result = _lifecycle.then((_) => operation());
    _lifecycle = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _start() async {
    if (running) return;
    final directory = Directory(p.dirname(discoveryPath));
    await directory.create(recursive: true);
    // Retain the lock file after shutdown: removing it can let another process
    // lock a different file at the same path while an existing holder runs.
    final lock = await File(p.join(directory.path, 'server.lock'))
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      await lock.close();
      throw const ControlException(
        'already_running',
        'Another control server is already using this home.',
      );
    }
    _lock = lock;
    try {
      final random = Random.secure();
      _token = base64Url
          .encode(List<int>.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.autoCompress = false;
      _server = server;
      server.listen((request) {
        // Each request handles all errors locally; no exception text is sent.
        unawaited(_handle(request));
      });
      final temporary = File('$discoveryPath.$_token.tmp');
      try {
        await temporary.writeAsString(
          jsonEncode({'url': url, 'token': _token, 'pid': pid, 'protocol': 1}),
          flush: true,
        );
        await temporary.rename(discoveryPath);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } catch (_) {
      await _stop();
      rethrow;
    }
  }

  Future<void> _stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    await _dispatch;
    // Never delete a replacement discovery belonging to another owner.
    if (_token != null) {
      final file = File(discoveryPath);
      try {
        final discovery = jsonDecode(await file.readAsString());
        if (discovery is Map && discovery['token'] == _token) {
          await file.delete();
        }
      } on FileSystemException {
        // Already absent or temporarily unavailable.
      } on FormatException {
        // A replacement file that we do not own.
      }
    }
    _token = null;
    final lock = _lock;
    _lock = null;
    if (lock != null) {
      await lock.unlock();
      await lock.close();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.headers.value('origin') != null) {
        _error(
          request,
          403,
          'origin_forbidden',
          'Browser requests are forbidden.',
        );
      } else if (!_authenticated(request.headers.value('authorization'))) {
        _error(request, 401, 'unauthorized', 'Authentication required.');
      } else if (request.method == 'GET' && request.uri.path == '/v1/tools') {
        _json(request, 200, {'tools': listTools()});
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/tools/call') {
        final body = await _readBody(request);
        if (body is! Map<String, dynamic> ||
            body['name'] is! String ||
            (body['name'] as String).isEmpty ||
            body['arguments'] is! Map<String, dynamic>) {
          throw const ControlException(
            'invalid_request',
            'Expected a tool name and an arguments object.',
          );
        }
        final operation = _dispatch.then((_) async {
          final result = await callTool(
            body['name'] as String,
            body['arguments'] as Map<String, dynamic>,
          );
          _json(request, 200, result);
        });
        _dispatch = operation.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        await operation;
      } else {
        _error(request, 404, 'not_found', 'Unknown control endpoint.');
      }
    } on _BodyTooLarge {
      _error(request, 413, 'body_too_large', 'Request body exceeds 2 MiB.');
    } on FormatException {
      _error(request, 400, 'invalid_json', 'Expected valid UTF-8 JSON.');
    } on ControlException catch (error) {
      final status = switch (error.code) {
        'revision_conflict' || 'conflict' || 'busy' || 'render_busy' => 409,
        'not_found' || 'unknown_tool' || 'page_not_found' => 404,
        _ => 400,
      };
      _error(request, status, error.code, error.message);
    } catch (_) {
      _error(request, 500, 'internal_error', 'Control operation failed.');
    } finally {
      try {
        await request.response.close();
      } catch (_) {
        // The caller may have disconnected or the service may be stopping.
      }
    }
  }

  bool _authenticated(String? authorization) {
    final expected = 'Bearer $_token';
    if (_token == null || authorization == null) return false;
    var difference = authorization.length ^ expected.length;
    for (var i = 0; i < expected.length; i++) {
      difference |=
          expected.codeUnitAt(i) ^
          (i < authorization.length ? authorization.codeUnitAt(i) : 0);
    }
    return difference == 0;
  }

  Future<dynamic> _readBody(HttpRequest request) async {
    const maximum = 2 * 1024 * 1024;
    if (request.contentLength > maximum) {
      unawaited(request.drain<void>().catchError((Object _) {}));
      throw const _BodyTooLarge();
    }
    final bytes = <int>[];
    final received = Completer<void>();
    // Keep draining after exceeding the cap. Cancelling the request stream can
    // destroy the socket before the caller receives the JSON error response.
    request.listen(
      (chunk) {
        if (received.isCompleted) return;
        if (bytes.length + chunk.length > maximum) {
          received.completeError(const _BodyTooLarge());
        } else {
          bytes.addAll(chunk);
        }
      },
      onDone: () {
        if (!received.isCompleted) received.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (!received.isCompleted) received.completeError(error, stack);
      },
    );
    await received.future;
    return jsonDecode(utf8.decode(bytes));
  }

  void _error(HttpRequest request, int status, String code, String message) {
    _json(request, status, {
      'error': {'code': code, 'message': message},
    });
  }

  void _json(HttpRequest request, int status, Map<String, Object?> value) {
    // Encode first so a callback's invalid result does not partially write JSON.
    final encoded = jsonEncode(value);
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..write(encoded);
  }
}

class _BodyTooLarge implements Exception {
  const _BodyTooLarge();
}
