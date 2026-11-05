import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image
import penna_relay as relay


def snapshot(number=1):
    layout = {"summary": {"caption": f"Safe daily scene {number}"}, "items": []}
    return {"title": f"Page {number}", "width": 64, "height": 64,
            "layout": layout, "source": copy.deepcopy(layout),
            "context": {"workspace": "test", "series": "daily", "page_number": number}}


class FakeController:
    def __init__(self, fail=(), queue=None, histories=None):
        self.calls = []
        self.submitted = []
        self.fail = set(fail)
        self.queue = queue or {"queue_running": [], "queue_pending": []}
        self.histories = histories or {}

    def assert_comfy_idle(self):
        if self.queue["queue_running"] or self.queue["queue_pending"]:
            raise RuntimeError("ComfyUI busy")

    def adopt_configured_server(self): self.calls.append("adopt")
    def image(self): self.calls.append("image")
    def chat(self):
        self.assert_comfy_idle()
        self.calls.append("chat")

    def api(self, base, path, body=None, timeout=5):
        if path == "/queue": return self.queue
        if path == "/prompt":
            self.assert_comfy_idle()
            prompt_id = f"task-{len(self.submitted) + 1}"
            self.submitted.append(body)
            self.histories[prompt_id] = {
                "status": {"status_str": "error" if len(self.submitted) in self.fail else "success"},
                "outputs": {"11": {"images": [{"filename": "fake.png", "subfolder": "", "type": "output"}]}}}
            return {"prompt_id": prompt_id}
        if path.startswith("/history/"):
            key = path.rsplit("/", 1)[-1]
            return {key: self.histories[key]} if key in self.histories else {}
        raise AssertionError(path)


class BatchTests(unittest.TestCase):
    def test_prepare_failure_keeps_total_and_cannot_resume_as_a_shorter_batch(self):
        import penna_batch
        second=snapshot(2);second['width']=65
        with self.assertRaises(penna_batch.BatchError):
            penna_batch.prepare_batch({'pages':[snapshot(1),second,snapshot(3)],'settings':{'loras':[]}},root=self.root)
        batch=next((self.root/'batches').iterdir())
        event=json.loads((batch/'events.ndjson').read_text(encoding='utf-8').splitlines()[-1])
        self.assertEqual(event['page_total'],3)
        with self.assertRaises(ValueError):
            penna_batch.run_batch(batch,FakeController())
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(patch.stopall)
        patch.object(relay, "OUTPUT", self.root).start()
        self.output = io.StringIO()
        self.capture = contextlib.redirect_stdout(self.output)
        self.capture.__enter__()
        self.addCleanup(self.capture.__exit__, None, None, None)
        raw = io.BytesIO()
        Image.new("RGB", (64, 64), "gray").save(raw, format="PNG")
        patch.object(relay.urllib.request, "urlopen", side_effect=lambda *a, **k: io.BytesIO(raw.getvalue())).start()

    def create(self, **kwargs):
        import penna_batch
        return penna_batch.prepare_batch({"title": "Daily", "pages": [snapshot(1), snapshot(2), snapshot(3)],
                                          "settings": {"steps": 1, "seed": 80, "loras": []}, **kwargs}, root=self.root)

    def load(self, batch): return json.loads((batch / "batch.json").read_text(encoding="utf-8"))

    def test_batch_saves_all_snapshots_and_switches_gpu_once(self):
        import penna_batch
        batch = self.create()
        saved = self.load(batch)
        self.assertEqual([relay_data["status"] for relay_data in saved["pages"]], ["saved"] * 3)
        self.assertEqual([json.loads((Path(p["job_dir"]) / "page.json").read_text(encoding="utf-8"))["settings"]["seed"]
                          for p in saved["pages"]], [80, 81, 82])
        controller = FakeController()
        result = penna_batch.run_batch(batch, controller)
        self.assertEqual(result["status"], "done")
        self.assertEqual(controller.calls, ["adopt", "image", "chat"])
        self.assertEqual(len(controller.submitted), 3)
        self.assertTrue(all(Path(p["image"]).is_file() for p in result["pages"]))
        events = [json.loads(line) for line in self.output.getvalue().splitlines()]
        self.assertEqual([e["stage"] for e in events if e["stage"] in ("done", "error")], ["done"])
        self.assertTrue(all("batch_dir" in e and "pages" in e for e in events))
        self.assertTrue(all(e["page_index"] in (1, 2, 3) for e in events if e["stage"] == "page_done"))

    def test_resume_skips_completed_pages_without_switching_or_resubmitting(self):
        import penna_batch
        batch = self.create()
        penna_batch.run_batch(batch, FakeController())
        before = {p: p.read_bytes() for p in batch.rglob("page.png")}
        controller = FakeController()
        penna_batch.run_batch(batch, controller)
        self.assertEqual(controller.calls, [])
        self.assertEqual(controller.submitted, [])
        self.assertEqual(before, {p: p.read_bytes() for p in batch.rglob("page.png")})

    def test_failed_page_is_recorded_and_later_pages_finish(self):
        import penna_batch
        batch = self.create()
        controller = FakeController(fail={2})
        with self.assertRaises(RuntimeError): penna_batch.run_batch(batch, controller)
        result = self.load(batch)
        self.assertEqual([p["status"] for p in result["pages"]], ["done", "error", "done"])
        self.assertIn("ComfyUI", result["pages"][1]["error"])
        self.assertEqual(controller.calls, ["adopt", "image", "chat"])

    def test_independent_redo_retains_all_previous_page_versions(self):
        import penna_batch
        batch = self.create()
        penna_batch.run_batch(batch, FakeController())
        before = {p: p.read_bytes() for p in batch.rglob("page.png")}
        changed = snapshot(2)
        changed["layout"]["summary"]["caption"] = "A different safe daily scene"
        redo = penna_batch.prepare_batch({"pages": [changed], "settings": {"seed": 81, "steps": 1, "loras": []}}, root=self.root)
        penna_batch.run_batch(redo, FakeController())
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        self.assertNotEqual(batch, redo)
        self.assertEqual(self.load(redo)["pages"][0]["context"]["page_number"], 2)

    def test_resume_missing_history_never_resubmits(self):
        import penna_batch
        batch = self.create()
        data = self.load(batch)
        job = Path(data["pages"][0]["job_dir"])
        manifest = json.loads((job / "manifest.json").read_text(encoding="utf-8"))
        manifest.update(status="rendering", prompt_id="lost-task")
        relay.write_json(job / "manifest.json", manifest)
        controller = FakeController()
        with self.assertRaises(RuntimeError): penna_batch.run_batch(batch, controller)
        self.assertEqual(len(controller.submitted), 2)
        self.assertIn("历史", self.load(batch)["pages"][0]["error"])

    def test_resume_running_task_waits_without_duplicate_submission_or_chat(self):
        import penna_batch
        batch = self.create()
        data = self.load(batch)
        job = Path(data["pages"][0]["job_dir"])
        manifest = json.loads((job / "manifest.json").read_text(encoding="utf-8"))
        manifest.update(status="rendering", prompt_id="owned-task")
        relay.write_json(job / "manifest.json", manifest)
        controller = FakeController(queue={"queue_running": [[1, "owned-task", {}, {}, []]], "queue_pending": []})
        with self.assertRaises(RuntimeError): penna_batch.run_batch(batch, controller, timeout=0)
        self.assertEqual(controller.submitted, [])
        self.assertNotIn("chat", controller.calls)
        self.assertIn("busy", self.load(batch)["restore_error"])

    def test_resume_rejects_job_outside_batch_before_gpu_actions(self):
        import penna_batch
        batch = self.create()
        data = self.load(batch)
        data["pages"][0]["job_dir"] = str(self.root / "outside")
        relay.write_json(batch / "batch.json", data)
        controller = FakeController()
        with self.assertRaises(ValueError): penna_batch.run_batch(batch, controller)
        self.assertEqual(controller.calls, [])

    def test_changed_snapshot_is_not_silently_skipped(self):
        import penna_batch
        batch = self.create()
        penna_batch.run_batch(batch, FakeController())
        job = Path(self.load(batch)["pages"][0]["job_dir"])
        value = json.loads((job / "snapshot.json").read_text(encoding="utf-8"))
        value["layout"]["summary"]["caption"] = "changed"
        relay.write_json(job / "snapshot.json", value)
        controller = FakeController()
        with self.assertRaises(ValueError): penna_batch.run_batch(batch, controller)
        self.assertEqual(controller.calls, [])

    def test_resume_rejects_changed_page_identity_before_gpu_actions(self):
        import penna_batch
        batch = self.create()
        data = self.load(batch)
        data["pages"][0]["context"]["page_number"] = 99
        relay.write_json(batch / "batch.json", data)
        controller = FakeController()
        with self.assertRaises(ValueError): penna_batch.run_batch(batch, controller)
        self.assertEqual(controller.calls, [])

    def test_unchanged_pages_skip_even_if_previous_process_stopped_after_page_commit(self):
        import penna_batch
        batch = self.create()
        penna_batch.run_batch(batch, FakeController())
        data = self.load(batch)
        data["pages"][0].update(status="rendering", image=None)
        relay.write_json(batch / "batch.json", data)
        controller = FakeController()
        self.assertEqual(penna_batch.run_batch(batch, controller)["status"], "done")
        self.assertEqual(controller.calls, [])

    def test_explicit_redo_keeps_old_versions_inside_same_batch(self):
        import penna_batch
        batch = self.create(skip_completed=False)
        penna_batch.run_batch(batch, FakeController())
        before = {p: p.read_bytes() for p in batch.rglob("page.png")}
        result = penna_batch.run_batch(batch, FakeController())
        self.assertEqual(len(list(batch.rglob("page.png"))), 6)
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        self.assertTrue(all(len(page["versions"]) == 2 for page in result["pages"]))

    def test_unknown_http_submission_result_is_not_submitted_again(self):
        import penna_batch
        batch = self.create()
        job = Path(self.load(batch)["pages"][0]["job_dir"])
        manifest = json.loads((job / "manifest.json").read_text(encoding="utf-8"))
        manifest.update(status="submitting", submission_started=True)
        relay.write_json(job / "manifest.json", manifest)
        controller = FakeController()
        with self.assertRaises(RuntimeError): penna_batch.run_batch(batch, controller)
        self.assertEqual(len(controller.submitted), 2)
        self.assertIn("提交结果未知", self.load(batch)["pages"][0]["error"])

    def test_restore_failure_preserves_completed_pages_and_resume_only_restores_chat(self):
        import penna_batch
        batch = self.create()
        controller = FakeController()
        controller.chat = lambda: (_ for _ in ()).throw(RuntimeError("LLM unavailable"))
        with self.assertRaises(RuntimeError): penna_batch.run_batch(batch, controller)
        result = self.load(batch)
        self.assertEqual([p["status"] for p in result["pages"]], ["done"] * 3)
        self.assertTrue(result["gpu_restore_pending"])
        resume = FakeController()
        self.assertEqual(penna_batch.run_batch(batch, resume)["status"], "done")
        self.assertEqual(resume.calls, ["chat"])
        self.assertEqual(resume.submitted, [])

    def test_cli_batch_validation_error_keeps_complete_batch_event_schema(self):
        import sys
        with patch.object(sys, "argv", ["penna_relay.py", "--resume-batch", str(self.root / "outside")]), \
                patch.object(relay, "controller_lock", contextlib.nullcontext):
            self.assertEqual(relay.main(), 1)
        event = json.loads(self.output.getvalue().splitlines()[-1])
        self.assertEqual(event["stage"], "error")
        self.assertEqual(event["batch_dir"], str((self.root / "outside").resolve()))
        self.assertEqual(event["pages"], [])

    def test_resume_retries_confirmed_failed_page_as_new_version_only(self):
        import penna_batch
        batch = self.create()
        controller = FakeController(fail={2})
        with self.assertRaises(RuntimeError): penna_batch.run_batch(batch, controller)
        before = {p: p.read_bytes() for p in batch.rglob("page.png")}
        failed_job = self.load(batch)["pages"][1]["job_dir"]
        result = penna_batch.run_batch(batch, controller)
        self.assertEqual(result["status"], "done")
        self.assertEqual(len(controller.submitted), 4)
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        self.assertEqual(len(result["pages"][1]["versions"]), 2)
        self.assertNotEqual(result["pages"][1]["job_dir"], failed_job)
        self.assertEqual(json.loads((Path(failed_job) / "manifest.json").read_text(encoding="utf-8"))["status"], "error")

    def test_batch_cli_remembers_settings_without_using_services_or_user_settings(self):
        import sys
        settings = {"steps": 1, "seed": 80, "loras": [], "cfg": 2, "bubble": "cloud"}
        request = self.root / "request.json"
        relay.write_json(request, {"pages": [snapshot(1)], "settings": settings})
        fake_script = self.root / "penna_relay.py"
        with patch.object(sys, "argv", [str(fake_script), "--batch", str(request), "--prepare-only"]), \
                patch.object(relay.CONFIG, "home", self.root), \
                patch.object(relay, "controller_lock", contextlib.nullcontext):
            self.assertEqual(relay.main(), 0)
        self.assertEqual(json.loads((self.root / "relay-settings.json").read_text(encoding="utf-8")), settings)

    def test_batch_root_snapshot_changes_are_not_ignored_on_resume(self):
        import penna_batch
        batch = self.create()
        saved = json.loads((batch / "snapshots.json").read_text(encoding="utf-8"))
        saved[0]["context"]["page_number"] = 99
        relay.write_json(batch / "snapshots.json", saved)
        controller = FakeController()
        with self.assertRaises(ValueError): penna_batch.run_batch(batch, controller)
        self.assertEqual(controller.calls, [])

    def test_running_task_finishes_on_resume_without_duplicate_submission(self):
        import penna_batch
        batch = self.create()
        job = Path(self.load(batch)["pages"][0]["job_dir"])
        manifest = json.loads((job / "manifest.json").read_text(encoding="utf-8"))
        manifest.update(status="rendering", prompt_id="old-running")
        relay.write_json(job / "manifest.json", manifest)

        class CompletingController(FakeController):
            polls = 0
            def api(self, base, path, body=None, timeout=5):
                if path == "/history/old-running":
                    self.polls += 1
                    if self.polls >= 2:
                        self.queue = {"queue_running": [], "queue_pending": []}
                        return {"old-running": {"status": {"status_str": "success"},
                                                "outputs": {"11": {"images": [
                                                    {"filename": "fake.png", "subfolder": "", "type": "output"}]}}}}
                    return {}
                return super().api(base, path, body, timeout)

        controller = CompletingController(queue={"queue_running": [[1, "old-running", {}, {}, []]], "queue_pending": []})
        with patch.object(relay.time, "sleep"):
            result = penna_batch.run_batch(batch, controller)
        self.assertEqual(result["status"], "done")
        self.assertEqual(len(controller.submitted), 2)
        self.assertEqual(controller.calls, ["adopt", "image", "chat"])
        self.assertEqual(json.loads((job / "manifest.json").read_text(encoding="utf-8"))["prompt_id"], "old-running")

    def test_unrelated_queued_task_prevents_gpu_switch_and_new_submissions(self):
        import penna_batch
        batch = self.create()
        controller = FakeController(queue={"queue_running": [], "queue_pending": [[1, "external-task", {}, {}, []]]})
        with self.assertRaisesRegex(RuntimeError, "busy"):
            penna_batch.run_batch(batch, controller)
        self.assertEqual(controller.calls, [])
        self.assertEqual(controller.submitted, [])


if __name__ == "__main__": unittest.main()
