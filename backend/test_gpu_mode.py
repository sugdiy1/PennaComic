import unittest
import json
from pathlib import Path
import tempfile
from unittest.mock import Mock, patch

import gpu_mode


class GuardTests(unittest.TestCase):
    def setUp(self):
        mode = patch.object(gpu_mode, "MODE", "managed")
        mode.start()
        self.addCleanup(mode.stop)

    def test_busy_comfy_refuses_before_unloading_or_starting_llm(self):
        c = gpu_mode.Controller()
        c.api = Mock(return_value={"queue_running": [[1, "job"]], "queue_pending": []})
        with patch.object(c, "start_owned") as start:
            with self.assertRaisesRegex(RuntimeError, "ComfyUI busy"):
                c.chat()
            start.assert_not_called()
        self.assertEqual(c.api.call_count, 1)

    def test_busy_llm_is_not_killed(self):
        c = gpu_mode.Controller()
        c.api = Mock(side_effect=[{"is_sleeping": False}, [{"is_processing": True}]])
        with patch.object(c, "stop_owned") as stop, patch.object(c, "port_open", return_value=True):
            with self.assertRaisesRegex(RuntimeError, "LLM busy"):
                c.image()
            stop.assert_not_called()

    def test_unowned_server_is_not_killed(self):
        c = gpu_mode.Controller()
        with patch.object(c, "owned_process", return_value=None), patch.object(c, "port_open", return_value=True):
            with self.assertRaisesRegex(RuntimeError, "not owned"):
                c.stop_owned()

    def test_recycled_pid_is_not_owned(self):
        c = gpu_mode.Controller()
        fake = Mock()
        fake.create_time.return_value = 2000
        with patch.object(c, "read_state", return_value={"pid": 123, "created": 1000}), patch.object(gpu_mode.psutil, "Process", return_value=fake):
            self.assertIsNone(c.owned_process())

    def test_adoption_rejects_other_executable_on_port(self):
        c = gpu_mode.Controller()
        process = Mock(); process.exe.return_value=r'C:\Windows\System32\notepad.exe'
        listener = Mock(pid=123, status=gpu_mode.psutil.CONN_LISTEN)
        listener.laddr.port=8090
        with patch.object(c,'owned_process',return_value=None), patch.object(c,'port_open',return_value=True), \
             patch.object(gpu_mode.psutil,'net_connections',return_value=[listener]), \
             patch.object(gpu_mode.psutil,'Process',return_value=process):
            with self.assertRaisesRegex(RuntimeError,'其他程序'):
                c.adopt_configured_server()
            process.terminate.assert_not_called()

    def test_ui_workflow_refused_before_stopping_llm(self):
        c = gpu_mode.Controller()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ui.json"
            path.write_text(json.dumps({"nodes": [], "links": []}), encoding="utf-8")
            with patch.object(c, "image") as image:
                with self.assertRaisesRegex(ValueError, "API workflow"):
                    c.render(path)
                image.assert_not_called()

    def test_failed_image_does_not_restart_llm(self):
        c = gpu_mode.Controller()
        c.api = Mock(side_effect=[{"queue_running": [], "queue_pending": []},
                                 {"prompt_id": "test-job"},
                                 {"test-job": {"status": {"status_str": "error"}}}])
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "api.json"
            path.write_text(json.dumps({"1": {"class_type": "SaveImage", "inputs": {}}}), encoding="utf-8")
            with patch.object(c, "image"), patch.object(c, "chat") as chat:
                with self.assertRaisesRegex(RuntimeError, "job failed"):
                    c.render(path)
                chat.assert_not_called()


if __name__ == "__main__":
    unittest.main()
