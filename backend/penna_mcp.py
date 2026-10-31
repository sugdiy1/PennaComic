"""Penna stdio MCP adapter. Python standard library only; stdout is MCP JSON.

Usage: python penna_mcp.py --home <Penna data directory> [--check]
"""
import argparse
import json
from pathlib import Path
import re
import sys
import urllib.error
import urllib.request


PROTOCOLS = ('2024-11-05', '2025-03-26', '2025-06-18', '2025-11-25')
MAX_RESPONSE = 16 * 1024 * 1024
MAX_REQUEST = 2 * 1024 * 1024


class BridgeError(Exception):
    """Safe local connection failure, without raw URLs or credentials."""


class RpcError(Exception):
    def __init__(self, code, message):
        self.code = code
        self.message = message


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def reject_constant(value):
    raise ValueError('Non-finite JSON number')


def decode_json(data):
    return json.loads(data, parse_constant=reject_constant)


class PennaConnection:
    def __init__(self, home):
        self.path = Path(home) / 'control' / 'connection.json'
        self.token = ''
        # Never send local bearer credentials through environment-configured proxies.
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def discovery(self):
        try:
            with self.path.open('rb') as source:
                data = source.read(65537)
            if len(data) > 65536:
                raise ValueError()
            data = decode_json(data)
            if not isinstance(data, dict) or type(data.get('protocol')) is not int or data['protocol'] != 1:
                raise ValueError()
            url, token = data.get('url'), data.get('token')
            # Match a literal IPv4 loopback authority only: no DNS, credentials,
            # fragments, alternate numeric hosts, queries, paths or redirects.
            match = re.fullmatch(r'http://127\.0\.0\.1:([0-9]{1,5})', url or '')
            if not match or not 1 <= int(match.group(1)) <= 65535:
                raise ValueError()
            if not isinstance(token, str) or not re.fullmatch(r'[!-~]{1,4096}', token):
                raise ValueError()
            self.token = token
            return url
        except (OSError, ValueError, TypeError, RecursionError):
            raise BridgeError('Penna connection unavailable or invalid. Open Penna and enable agent control; verify --home.') from None

    def redact(self, value):
        if isinstance(value, str):
            return value.replace(self.token, '[redacted]') if self.token else value
        if isinstance(value, list):
            return [self.redact(item) for item in value]
        if isinstance(value, dict):
            return {self.redact(key): self.redact(item) for key, item in value.items()}
        return value

    def request(self, path, payload=None):
        url = self.discovery()
        body = None if payload is None else json.dumps(payload, ensure_ascii=True, allow_nan=False).encode('utf-8')
        request = urllib.request.Request(url + path, data=body, headers={
            'Authorization': 'Bearer ' + self.token, 'Accept': 'application/json',
            'Content-Type': 'application/json'})
        try:
            response = self.opener.open(request, timeout=15)
        except urllib.error.HTTPError as error:
            # HTTPError is also a response stream; do not surface its URL/headers.
            response = error
        except (OSError, ValueError):
            raise BridgeError('Cannot reach Penna. Verify it is open and agent control is enabled.') from None
        try:
            with response:
                data = response.read(MAX_RESPONSE + 1)
                status = response.status
            if len(data) > MAX_RESPONSE:
                raise ValueError()
            value = self.redact(decode_json(data))
        except (OSError, ValueError, TypeError, RecursionError):
            raise BridgeError('Penna returned an invalid or oversized response.') from None
        if not 200 <= status < 300:
            if isinstance(value, dict) and isinstance(value.get('error'), dict):
                error = value['error']
                if isinstance(error.get('code'), str) and isinstance(error.get('message'), str):
                    return False, {'error': {'code': error['code'], 'message': error['message']}}
            raise BridgeError('Penna refused the request (HTTP %s).' % status)
        return True, value

    def list_tools(self):
        ok, value = self.request('/v1/tools')
        if not ok or not isinstance(value, dict) or not isinstance(value.get('tools'), list):
            raise BridgeError('Penna tool list unavailable.')
        return {'tools': value['tools']}


def dispatch(connection, method, params):
    if method == 'initialize':
        version = params.get('protocolVersion')
        return {'protocolVersion': version if version in PROTOCOLS else PROTOCOLS[-1],
                'capabilities': {'tools': {}},
                'serverInfo': {'name': 'penna', 'version': '1.0.0'}}
    if method == 'ping':
        return {}
    if method == 'tools/list':
        return connection.list_tools()
    if method == 'tools/call':
        name, arguments = params.get('name'), params.get('arguments', {})
        if not isinstance(name, str) or not name or not isinstance(arguments, dict):
            raise RpcError(-32602, 'tools/call requires a name and object arguments.')
        try:
            ok, result = connection.request('/v1/tools/call', {'name': name, 'arguments': arguments})
        except BridgeError as error:
            ok, result = False, {'error': {'code': 'connection_unavailable', 'message': str(error)}}
        return {'content': [{'type': 'text', 'text': json.dumps(result, ensure_ascii=False, allow_nan=False)}],
                'isError': not ok}
    raise RpcError(-32601, 'Method not found.')


def error_reply(id, code, message):
    return {'jsonrpc': '2.0', 'id': id, 'error': {'code': code, 'message': message}}


def handle_line(connection, line):
    try:
        request = decode_json(line)
    except (ValueError, UnicodeError, RecursionError):
        return error_reply(None, -32700, 'Parse error.')
    if (not isinstance(request, dict) or request.get('jsonrpc') != '2.0'
            or not isinstance(request.get('method'), str)
            or ('id' in request and (isinstance(request['id'], bool)
                or not isinstance(request['id'], (str, int))))):
        return error_reply(None, -32600, 'Invalid request.')
    if 'id' not in request:
        return None  # Notifications must never trigger calls or produce replies.
    id = request['id']
    params = request.get('params', {})
    if not isinstance(params, dict):
        return error_reply(id, -32602, 'Parameters must be an object.')
    try:
        return {'jsonrpc': '2.0', 'id': id, 'result': dispatch(connection, request['method'], params)}
    except RpcError as error:
        return error_reply(id, error.code, error.message)
    except BridgeError as error:
        return error_reply(id, -32000, str(error))
    except Exception:
        # Never echo untrusted input, exception strings, headers or tracebacks.
        return error_reply(id, -32603, 'Internal bridge error.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', required=True, help='Penna data directory (PENNA_HOME)')
    parser.add_argument('--check', action='store_true', help='Read-only connectivity check; no MCP session')
    args = parser.parse_args()
    connection = PennaConnection(args.home)
    if args.check:
        try:
            tools = connection.list_tools()['tools']
            print('Connected to Penna: %s tools available.' % len(tools))
            return 0
        except BridgeError as error:
            print(str(error), file=sys.stderr)
            return 1
    while True:
        line = sys.stdin.buffer.readline(MAX_REQUEST + 1)
        if not line:
            return 0
        if len(line) > MAX_REQUEST:
            while line and not line.endswith(b'\n'):
                line = sys.stdin.buffer.readline(MAX_REQUEST + 1)
            reply = error_reply(None, -32600, 'Request exceeds 2 MiB.')
        elif not line.strip():
            continue
        else:
            reply = handle_line(connection, line)
        if reply is not None:
            # ASCII JSON escapes preserve every request ID, including lone
            # surrogates, without emitting invalid UTF-8 or ending the session.
            encoded = json.dumps(connection.redact(reply), ensure_ascii=True, allow_nan=False).encode('utf-8')
            sys.stdout.buffer.write(encoded + b'\n')
            sys.stdout.buffer.flush()


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
