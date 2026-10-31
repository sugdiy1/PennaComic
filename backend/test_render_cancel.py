"""Cooperative cancellation tests; all controller traffic is synthetic."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import penna_relay as relay
import penna_batch
from test_penna_batch import FakeController, snapshot
from render_cancel import RenderCancelled, RenderCancelToken


class CancelController(FakeController):
    def api(self, base, path, body=None, timeout=5):
        if body is not None and path in ('/queue', '/interrupt'):
            self.calls.append((path, body))
            if path == '/queue':
                self.queue['queue_pending'] = [e for e in self.queue['queue_pending']
                                                if e[1] not in body['delete']]
            else:
                self.queue['queue_running'] = []
            return {}
        return super().api(base, path, body, timeout)


class RenderCancelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.marker = self.home / 'control' / 'cancel' / 'task-1.json'
        self.marker.parent.mkdir(parents=True)
        self.token = RenderCancelToken(self.marker, home=self.home)
        self.addCleanup(patch.stopall)
        patch.object(relay, 'OUTPUT', self.home / 'renders').start()
        self.capture = contextlib.redirect_stdout(io.StringIO())
        self.capture.__enter__()
        self.addCleanup(self.capture.__exit__, None, None, None)

    def test_missing_marker_is_not_cancelled_and_paths_are_confined(self):
        self.token.check()
        for path in [Path('relative.json'), self.home / 'elsewhere.json',
                     self.marker.parent / 'nested' / 'task.json',
                     self.marker.with_suffix('.txt'), self.marker.parent / '../outside.json']:
            with self.assertRaises(ValueError): RenderCancelToken(path, home=self.home)
        self.marker.write_text('{}')
        with self.assertRaises(RenderCancelled): self.token.check()

    def test_idle_cancellation_never_sends_interrupt(self):
        self.marker.touch()
        controller = CancelController()
        with self.assertRaises(RenderCancelled): self.token.check(controller, 'own')
        self.assertEqual(controller.calls, [])

    def test_deletes_only_owned_pending_prompt(self):
        self.marker.touch()
        controller = CancelController(queue={'queue_running': [[1, 'other']],
            'queue_pending': [[2, 'own'], [3, 'other-pending']]})
        with self.assertRaises(RenderCancelled): self.token.check(controller, 'own')
        self.assertEqual(controller.calls, [('/queue', {'delete': ['own']})])
        self.assertEqual(controller.queue['queue_running'], [[1, 'other']])
        self.assertEqual(controller.queue['queue_pending'], [[3, 'other-pending']])

    def test_interrupts_only_matching_owned_running_prompt(self):
        self.marker.touch()
        controller = CancelController(queue={'queue_running': [[1, 'own']], 'queue_pending': []})
        with self.assertRaises(RenderCancelled): self.token.check(controller, 'own')
        self.assertEqual(controller.calls, [('/interrupt', {'prompt_id': 'own'})])

    def test_unrelated_running_and_queue_race_never_interrupted(self):
        self.marker.touch()
        controller = CancelController(queue={'queue_running': [[1, 'other']], 'queue_pending': []})
        with self.assertRaises(RenderCancelled): self.token.check(controller, 'own')
        self.assertEqual(controller.calls, [])
        class Raced(CancelController):
            reads = 0
            def api(self, base, path, body=None, timeout=5):
                if path == '/queue' and body is None:
                    self.reads += 1
                    if self.reads == 2: self.queue['queue_running'] = [[1, 'other']]
                return super().api(base, path, body, timeout)
        controller = Raced(queue={'queue_running': [[1, 'own']], 'queue_pending': []})
        with self.assertRaises(RenderCancelled): self.token.check(controller, 'own')
        self.assertEqual(controller.calls, [])

    def test_cancel_on_poll_marks_job_cancelled_and_never_resubmits(self):
        job = relay.prepare(snapshot(), root=relay.OUTPUT)
        token = self.token
        marker = self.marker
        class CancelsOnSubmit(CancelController):
            def api(self, base, path, body=None, timeout=5):
                result = super().api(base, path, body, timeout)
                if path == '/prompt':
                    self.queue['queue_running'] = [[1, result['prompt_id']]]
                    marker.touch()
                return result
        controller = CancelsOnSubmit()
        with self.assertRaises(RenderCancelled): relay.run(job, controller, cancel_token=token)
        self.assertEqual(len(controller.submitted), 1)
        self.assertEqual(json.loads((job / 'manifest.json').read_text(encoding='utf-8'))['status'], 'cancelled')
        with self.assertRaises(RenderCancelled): relay.run(job, controller, cancel_token=token)
        self.assertEqual(len(controller.submitted), 1)

    def test_midbatch_cancel_preserves_completed_page_and_stops_next_submission(self):
        batch = penna_batch.prepare_batch({'pages': [snapshot(1), snapshot(2)],
                                           'settings': {'loras': []}}, root=relay.OUTPUT)
        original_event = penna_batch.batch_event
        def event(*args, **kwargs):
            original_event(*args, **kwargs)
            if args[2] == 'page_done': self.marker.touch()
        raw = io.BytesIO()
        relay.Image.new('RGB', (64, 64)).save(raw, format='PNG')
        controller = CancelController()
        with patch.object(penna_batch, 'batch_event', side_effect=event), \
             patch.object(relay.urllib.request, 'urlopen', side_effect=lambda *a, **k: io.BytesIO(raw.getvalue())):
            with self.assertRaises(RenderCancelled):
                penna_batch.run_batch(batch, controller, cancel_token=self.token)
        saved = json.loads((batch / 'batch.json').read_text(encoding='utf-8'))
        self.assertEqual(saved['status'], 'cancelled')
        self.assertEqual([p['status'] for p in saved['pages']], ['done', 'saved'])
        self.assertEqual(len(controller.submitted), 1)
        self.assertTrue(Path(saved['pages'][0]['image']).is_file())

    def test_cancelled_batch_resume_removes_owned_queue_and_keeps_busy_restore_pending(self):
        batch = penna_batch.prepare_batch({'pages': [snapshot()],
                                           'settings': {'loras': []}}, root=relay.OUTPUT)
        saved = json.loads((batch / 'batch.json').read_text(encoding='utf-8'))
        job = Path(saved['pages'][0]['job_dir'])
        manifest = json.loads((job / 'manifest.json').read_text(encoding='utf-8'))
        manifest.update(prompt_id='own', status='rendering')
        relay.write_json(job / 'manifest.json', manifest)
        saved['gpu_restore_pending'] = True
        relay.write_json(batch / 'batch.json', saved)
        self.marker.touch()
        controller = CancelController(queue={'queue_running': [[1, 'other']],
                                              'queue_pending': [[2, 'own']]})
        with self.assertRaises(RenderCancelled):
            penna_batch.run_batch(batch, controller, cancel_token=self.token)
        self.assertEqual(controller.calls, [('/queue', {'delete': ['own']})])
        self.assertTrue(json.loads((batch / 'batch.json').read_text(encoding='utf-8'))['gpu_restore_pending'])

    def test_cancel_at_submitting_can_resume_without_ambiguous_submission(self):
        job = relay.prepare(snapshot(), root=relay.OUTPUT)
        controller = CancelController()
        def on_stage(stage, message, **data):
            if stage == 'submitting': self.marker.touch()
        with self.assertRaises(RenderCancelled):
            relay.run(job, controller, cancel_token=self.token, event_callback=on_stage)
        self.assertEqual(controller.submitted, [])
        saved = json.loads((job / 'manifest.json').read_text(encoding='utf-8'))
        self.assertFalse(saved.get('submission_started', False))
        self.marker.unlink()
        raw = io.BytesIO()
        relay.Image.new('RGB', (64, 64)).save(raw, format='PNG')
        with patch.object(relay.urllib.request, 'urlopen',
                          side_effect=lambda *a, **k: io.BytesIO(raw.getvalue())):
            image = relay.run(job, controller, cancel_token=self.token)
        self.assertTrue(image.is_file())
        self.assertEqual(len(controller.submitted), 1)


if __name__ == '__main__':
    unittest.main()
