"""File-based cooperative cancellation, scoped to one owned render prompt."""
from pathlib import Path
import re

from runtime_config import CONFIG


class RenderCancelled(RuntimeError):
    emitted = False

    def __init__(self):
        super().__init__('渲染已取消，已完成的页面已保留。')


def prompt_ids(queue, key):
    result = set()
    for entry in queue.get(key, []):
        value = entry.get('prompt_id') if isinstance(entry, dict) else (
            entry[1] if isinstance(entry, (list, tuple)) and len(entry) > 1 else None)
        if isinstance(value, str): result.add(value)
    return result


class RenderCancelToken:
    def __init__(self, cancel_file=None, *, home=None):
        self.path = None
        if cancel_file is None: return
        raw = Path(cancel_file)
        root = (Path(home) if home is not None else CONFIG.home).resolve() / 'control' / 'cancel'
        path = raw.resolve()
        if (not raw.is_absolute() or path.parent != root
                or not re.fullmatch(r'[A-Za-z0-9_-]+\.json', path.name)):
            raise ValueError('取消标记必须为 home/control/cancel/<taskid>.json 的绝对路径。')
        self.path = path

    @property
    def cancelled(self):
        return self.path is not None and self.path.exists()

    def check(self, controller=None, prompt_id=None):
        if not self.cancelled: return
        if controller is not None and prompt_id:
            self._stop_owned(controller, prompt_id)
        raise RenderCancelled()

    @staticmethod
    def _stop_owned(controller, prompt_id):
        # Failure to inspect/stop must still cancel local scheduling. Never use
        # global queue clear; a timed-out request may already have taken effect.
        try:
            queue = controller.api(CONFIG.comfy_url, '/queue')
            if prompt_id in prompt_ids(queue, 'queue_pending'):
                controller.api(CONFIG.comfy_url, '/queue', {'delete': [prompt_id]})
            # Re-read immediately before interrupt to reduce completion races.
            if prompt_ids(queue, 'queue_running') == {prompt_id}:
                current = controller.api(CONFIG.comfy_url, '/queue')
                if prompt_ids(current, 'queue_running') == {prompt_id}:
                    controller.api(CONFIG.comfy_url, '/interrupt', {'prompt_id': prompt_id})
        except Exception:
            pass
