"""Real stdio subprocess and loopback HTTP tests; no Penna data or GPU."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest


SCRIPT = Path(__file__).with_name('penna_mcp.py')
TOKEN = 'test-secret-token'
DESCRIPTOR = {'name': 'penna_status', 'description': 'Status',
              'inputSchema': {'type': 'object', 'properties': {}}}


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.requests = []
        self.redirect = False
        self.raw_get = None
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def reply(self, status, value):
                data = json.dumps(value).encode()
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                owner.requests.append((self.path, self.headers.get('Authorization'), None))
                if owner.raw_get is not None:
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(owner.raw_get)))
                    self.end_headers()
                    self.wfile.write(owner.raw_get)
                    return
                if owner.redirect:
                    self.send_response(302)
                    self.send_header('Location', '/stolen')
                    self.end_headers()
                    return
                self.reply(200, {'tools': [DESCRIPTOR]})

            def do_POST(self):
                data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                owner.requests.append((self.path, self.headers.get('Authorization'), data))
                if data['name'] == 'conflict':
                    self.reply(409, {'error': {'code': 'revision_conflict', 'message': 'Read page again'}})
                elif data['name'] == 'leaky':
                    self.reply(500, {'error': {'code': 'failure', 'message': TOKEN}})
                else:
                    self.reply(200, {'ok': True, 'page': data['arguments']})

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.discovery = self.home / 'control' / 'connection.json'
        self.discovery.parent.mkdir()
        self.write_discovery()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def write_discovery(self, **changes):
        data = {'url': 'http://127.0.0.1:%s' % self.server.server_port,
                'token': TOKEN, 'protocol': 1}
        data.update(changes)
        self.discovery.write_text(json.dumps(data), encoding='utf-8')

    def run_bridge(self, requests=(), check=False):
        payload = '\n'.join(item if isinstance(item, str) else json.dumps(item)
                            for item in requests) + '\n'
        process = subprocess.run([sys.executable, str(SCRIPT), '--home', str(self.home)]
                                 + (['--check'] if check else []), input=payload,
                                 capture_output=True, text=True, encoding='utf-8', timeout=10)
        self.assertNotIn(TOKEN, process.stdout + process.stderr)
        return process

    def rpc(self, method, params=None, id=1):
        return {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params or {}}

    def test_initialize_ping_and_notifications_stdout_is_only_json(self):
        result = self.run_bridge([self.rpc('initialize', {'protocolVersion': '2025-03-26'}),
                                  {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
                                  self.rpc('ping', id=2)])
        self.assertEqual(result.returncode, 0, result.stderr)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(replies), 2)
        self.assertEqual(replies[0]['result']['protocolVersion'], '2025-03-26')
        self.assertEqual(replies[0]['result']['capabilities'], {'tools': {}})
        self.assertEqual(replies[1]['result'], {})
        self.assertEqual(self.requests, [])

    def test_list_and_call_forward_authenticated_requests(self):
        result = self.run_bridge([self.rpc('tools/list'), self.rpc('tools/call',
                                  {'name': 'penna_status', 'arguments': {'series': 2}}, id=2)])
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(replies[0]['result'], {'tools': [DESCRIPTOR]})
        content = replies[1]['result']['content'][0]
        self.assertEqual(content['type'], 'text')
        self.assertEqual(json.loads(content['text']), {'ok': True, 'page': {'series': 2}})
        self.assertEqual(self.requests[0][:2], ('/v1/tools', 'Bearer ' + TOKEN))
        self.assertEqual(self.requests[1], ('/v1/tools/call', 'Bearer ' + TOKEN,
                         {'name': 'penna_status', 'arguments': {'series': 2}}))

    def test_domain_failure_is_tool_error(self):
        result = self.run_bridge([self.rpc('tools/call', {'name': 'conflict'})])
        reply = json.loads(result.stdout)['result']
        self.assertTrue(reply['isError'])
        self.assertEqual(json.loads(reply['content'][0]['text'])['error']['code'], 'revision_conflict')

    def test_secret_in_upstream_error_is_redacted(self):
        result = self.run_bridge([self.rpc('tools/call', {'name': 'leaky'})])
        self.assertTrue(json.loads(result.stdout)['result']['isError'])

    def test_invalid_input_and_unknown_method_are_protocol_errors(self):
        result = self.run_bridge(['{', [], self.rpc('absent'),
                                  self.rpc('tools/call', {'name': 'x', 'arguments': []}),
                                  self.rpc('ping', id=5)])
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([r['error']['code'] for r in replies[:4]], [-32700, -32600, -32601, -32602])
        self.assertEqual(replies[-1]['id'], 5)

    def test_missing_discovery_still_allows_initialize(self):
        self.discovery.unlink()
        result = self.run_bridge([self.rpc('initialize'), self.rpc('tools/list', id=2)])
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertIn('result', replies[0])
        self.assertEqual(replies[1]['error']['code'], -32000)

    def test_discovery_rejects_non_loopback_or_ambiguous_urls(self):
        for url in ['http://example.com:80', 'http://localhost:80',
                    'https://127.0.0.1:80', 'http://127.0.0.1:80/path',
                    'http://user@127.0.0.1:80', 'http://127.0.0.1:80?x=1',
                    'http://127.0.0.1:80#fragment']:
            with self.subTest(url=url):
                self.write_discovery(url=url)
                result = self.run_bridge([self.rpc('tools/list')])
                self.assertEqual(json.loads(result.stdout)['error']['code'], -32000)
        self.assertEqual(self.requests, [])

    def test_redirect_is_not_followed(self):
        self.redirect = True
        result = self.run_bridge([self.rpc('tools/list')])
        self.assertIn('error', json.loads(result.stdout))
        self.assertEqual([r[0] for r in self.requests], ['/v1/tools'])

    def test_check_is_read_only_and_human_readable(self):
        before = self.discovery.read_bytes()
        result = self.run_bridge(check=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Connected', result.stdout)
        self.assertEqual([r[0] for r in self.requests], ['/v1/tools'])
        self.assertEqual(self.discovery.read_bytes(), before)

    def test_check_unavailable_exits_with_useful_error(self):
        self.discovery.unlink()
        result = self.run_bridge(check=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Penna', result.stderr)

    def test_check_deeply_nested_discovery_is_a_safe_failure(self):
        self.discovery.write_text('[' * 20000 + '0' + ']' * 20000, encoding='utf-8')
        result = self.run_bridge(check=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Penna', result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def test_surrogate_id_does_not_terminate_session(self):
        result = self.run_bridge([self.rpc('ping', id='\ud800'), self.rpc('ping', id=2)])
        self.assertEqual(result.returncode, 0, result.stderr)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(replies[0]['id'], '\ud800')
        self.assertEqual(replies[1], {'jsonrpc': '2.0', 'id': 2, 'result': {}})

    def test_check_deeply_nested_http_response_is_a_safe_failure(self):
        self.raw_get = ('[' * 1500 + '0' + ']' * 1500).encode('ascii')
        result = self.run_bridge(check=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Penna', result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def test_discovery_rejects_bad_protocol_and_header_tokens(self):
        for changes in [{'protocol': True}, {'protocol': 2}, {'token': ''},
                        {'token': 'a\r\nInjected: bad'}, {'token': 123}]:
            with self.subTest(changes=changes):
                self.write_discovery(**changes)
                result = self.run_bridge([self.rpc('tools/list')])
                self.assertEqual(json.loads(result.stdout)['error']['code'], -32000)
        self.assertEqual(self.requests, [])

    def test_notification_cannot_mutate_and_session_survives_invalid_json(self):
        result = self.run_bridge([{'jsonrpc': '2.0', 'method': 'tools/call',
                                  'params': {'name': 'penna_create_page'}},
                                 'NaN', self.rpc('ping', id=2)])
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(replies[0]['error']['code'], -32700)
        self.assertEqual(replies[1]['result'], {})
        self.assertEqual(self.requests, [])


if __name__ == '__main__':
    unittest.main()
