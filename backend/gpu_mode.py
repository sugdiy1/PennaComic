"""Windows GPU 分时控制：chat / image / render / status。日志只写 D 盘。

依赖现有 ComfyUI Python 中的 psutil，不安装任何软件。
只管理自己启动且 PID、创建时间、程序路径均匹配的服务进程。
这些命令必须由同一个漫画编排器串行调用；不会拦截用户直接访问 8188。
"""
import argparse
import contextlib
import json
import msvcrt
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

import psutil
from runtime_config import CONFIG
from urllib.parse import urlparse

ROOT = CONFIG.state
MODEL = CONFIG.llama_model.parent
EXE = CONFIG.llama_executable
COMFY = CONFIG.comfy_url
LLM = CONFIG.llm_url
MODE = CONFIG.mode



class Controller:
    def __init__(self, ctx=131072, vision=True, idle=300):
        self.ctx, self.vision, self.idle = ctx, vision, idle

    def api(self, base, path, body=None, timeout=5):
        data = None if body is None else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(base + path, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}

    def port_open(self):
        try:
            with socket.create_connection((urlparse(LLM).hostname, urlparse(LLM).port or 80), timeout=1):
                return True
        except OSError:
            return False

    def read_state(self):
        try:
            return json.loads((ROOT / "server-state.json").read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}

    def owned_process(self):
        state = self.read_state()
        if not state:
            return None
        try:
            p = psutil.Process(state["pid"])
            if abs(p.create_time() - state["created"]) > 0.01:
                return None
            if Path(p.exe()).resolve() != EXE.resolve():
                return None
            return p
        except psutil.NoSuchProcess:
            return None

    def gpu(self):
        row = subprocess.check_output(["nvidia-smi", "--id=0", "--query-gpu=memory.used,memory.free", "--format=csv,noheader,nounits"], text=True)
        used, free = (int(x.strip()) for x in row.strip().split(","))
        return {"used_MiB": used, "free_MiB": free}

    def assert_comfy_idle(self):
        q = self.api(COMFY, "/queue")
        if q.get("queue_running") or q.get("queue_pending"):
            raise RuntimeError("ComfyUI busy: wait for running and queued jobs before chat mode")

    def chat(self):
        if MODE == "external": return {"status": "external"}
        self.assert_comfy_idle()
        # /free 只是卸载 ComfyUI 的模型，不会关闭 ComfyUI 进程。
        self.api(COMFY, "/free", {"unload_models": True, "free_memory": True})
        return self.start_owned()

    def start_owned(self):
        if self.owned_process():
            return {"status": "already_running", "props": self.api(LLM, "/props"), "gpu": self.gpu()}
        if self.port_open():
            raise RuntimeError("Port 8090 belongs to a server not owned by this controller; close its launcher first")
        deadline = time.monotonic() + 30
        while self.gpu()["free_MiB"] < int(CONFIG.data.get("minimum_free_before_mib", 13000)):
            self.assert_comfy_idle()
            if time.monotonic() > deadline:
                raise RuntimeError("Need >=13000 MiB free before loading; close other GPU applications")
            time.sleep(1)
        self.assert_comfy_idle()
        if not EXE.is_file() or not CONFIG.llama_model.is_file() or not CONFIG.llama_args:
            raise RuntimeError("请配置 llama_executable、llama_model 和完整 llama_args；或使用 external 模式。")
        if urlparse(LLM).hostname not in ("127.0.0.1", "localhost", "::1"):
            raise RuntimeError("managed 模式只支持本机 LLM 地址")
        ROOT.mkdir(parents=True, exist_ok=True)
        args = [str(EXE), "-m", str(CONFIG.llama_model), *CONFIG.llama_args]
        # 不继承终端控制台，退出这个短命令不会关闭后台服务。
        with (ROOT / "llama-server.log").open("a", encoding="utf-8") as log:
            p = subprocess.Popen(args, cwd=MODEL, stdout=log, stderr=subprocess.STDOUT,
                                 creationflags=subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP)
        try:
            created = psutil.Process(p.pid).create_time()
            state = {"pid": p.pid, "created": created, "args": args}
            (ROOT / "server-state.json").write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                if p.poll() is not None:
                    raise RuntimeError(f"Server exited {p.returncode}; see {ROOT / 'llama-server.log'}")
                self.assert_comfy_idle()
                try:
                    ready = self.api(LLM, "/health", timeout=2).get("status") == "ok"
                except (OSError, urllib.error.URLError):
                    ready = False
                if ready:
                    stats = self.gpu()
                    if stats["free_MiB"] < int(CONFIG.data.get("minimum_free_after_mib", 3072)):
                        raise RuntimeError("Less than 3072 MiB free after loading; use --ctx 65536 --text-only")
                    return {"status": "ready", "pid": p.pid, "gpu": stats}
                time.sleep(0.5)
            raise TimeoutError("Server loading exceeded 180 seconds")
        except BaseException:
            if p.poll() is None:
                p.terminate()
                p.wait(timeout=15)
            (ROOT / "server-state.json").unlink(missing_ok=True)
            raise

    def stop_owned(self):
        p = self.owned_process()
        if p is None:
            if self.port_open():
                raise RuntimeError("LLM server not owned by this controller; refusing to kill it")
            return
        # psutil 会在 terminate 前检测 PID 是否已被复用。
        p.terminate()
        try:
            p.wait(timeout=15)
        except psutil.TimeoutExpired:
            p.kill()
            p.wait(timeout=10)
        (ROOT / "server-state.json").unlink(missing_ok=True)

    def adopt_configured_server(self):
        # 发行版只管理自己启动、PID与创建时间匹配的进程，不接管其他服务。
        if MODE == "external": return
        if not self.owned_process() and self.port_open():
            raise RuntimeError("LLM由其他程序启动；发行版不自动接管，请使用external模式。")

    def image(self):
        if MODE == "external": return {"status": "external"}
        if self.port_open():
            props = self.api(LLM, "/props")
            # /slots 可能唤醒模型；休眠时不查询它。
            if not props.get("is_sleeping", False):
                slots = self.api(LLM, "/slots")
                if any(s.get("is_processing") for s in slots):
                    raise RuntimeError("LLM busy: wait for generation to finish before image mode")
        self.stop_owned()
        return {"status": "image_mode", "gpu": self.gpu()}

    def render(self, workflow, timeout=1800):
        payload = json.loads(Path(workflow).read_text(encoding="utf-8-sig"))
        if "prompt" not in payload:
            payload = {"prompt": payload}
        if not isinstance(payload["prompt"], dict) or not payload["prompt"] or not all(
            isinstance(n, dict) and "class_type" in n for n in payload["prompt"].values()
        ):
            raise ValueError("Expected ComfyUI API workflow JSON; UI workflow JSON is not accepted")
        self.assert_comfy_idle()
        self.image()
        # 只提交用户显式指定的既有 API 工作流。等待任务完成后才恢复对话。
        result = self.api(COMFY, "/prompt", payload, timeout=30)
        prompt_id = result["prompt_id"]
        print(json.dumps({"prompt_id": prompt_id}), flush=True)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            history = self.api(COMFY, f"/history/{prompt_id}")
            item = history.get(prompt_id)
            if item:
                if item.get("status", {}).get("status_str") == "error":
                    raise RuntimeError(f"ComfyUI job failed; LLM remains stopped: {prompt_id}")
                return {"image": item, "chat": self.chat()}
            time.sleep(1)
        raise TimeoutError(f"ComfyUI job timed out; LLM remains stopped: {prompt_id}")

    def status(self):
        result = {"gpu": self.gpu(), "owned_pid": getattr(self.owned_process(), "pid", None)}
        for key, base, path in [("llm", LLM, "/props"), ("comfy", COMFY, "/queue")]:
            try:
                data = self.api(base, path)
                result[key] = {"is_sleeping": data.get("is_sleeping")} if key == "llm" else data
            except OSError as e:
                result[key] = str(e)
        return result


@contextlib.contextmanager
def controller_lock():
    # 同一个编排器的模式切换不能重叠。外部直接发到 8188/8090 的请求不受此锁控制。
    ROOT.mkdir(parents=True, exist_ok=True)
    with (ROOT / "controller.lock").open("a+b") as handle:
        handle.seek(0)
        if not handle.read(1):
            handle.write(b"0")
            handle.flush()
        handle.seek(0)
        try:
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as exc:
            raise RuntimeError("Another GPU operation is running") from exc
        try:
            yield
        finally:
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode", choices=["chat", "image", "render", "status"])
    p.add_argument("--ctx", type=int, choices=[65536, 131072], default=131072)
    p.add_argument("--text-only", action="store_true")
    p.add_argument("--idle", type=int, default=300)
    p.add_argument("--workflow")
    args = p.parse_args()
    c = Controller(args.ctx, not args.text_only, args.idle)
    try:
        with controller_lock():
            if args.mode == "render":
                if not args.workflow:
                    p.error("render requires --workflow")
                result = c.render(args.workflow)
            else:
                result = getattr(c, args.mode)()
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
