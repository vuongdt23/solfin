#!/usr/bin/env python3
"""macOS integration: synthetic HTTP video, managed thumbfast gating and recovery.
Requires Python 3, ffmpeg and mpv. No Jellyfin credentials or media required.
"""
import glob
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def wait_for(fn, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = fn()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError("Timed out: " + fn.__name__)


with tempfile.TemporaryDirectory(prefix="solfin-thumbnails-") as tmp:
    tmp = Path(tmp)
    video = tmp / "video.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=12",
                    "-t", "36", "-c:v", "libx264", "-g", "12", "-movflags", "+faststart", str(video)], check=True)
    media = video.read_bytes()

    class Server(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            start, end = 0, len(media) - 1
            partial = self.headers.get("Range")
            if partial:
                first, last = partial.removeprefix("bytes=").split("-", 1)
                start, end = int(first), int(last) if last else end
            self.send_response(206 if partial else 200)
            self.send_header("Content-Length", str(end - start + 1))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Type", "video/mp4")
            if partial:
                self.send_header("Content-Range", f"bytes {start}-{end}/{len(media)}")
            self.end_headers()
            try:
                self.wfile.write(media[start:end + 1])
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Server)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}/video.mp4"
    ipc_path = str(tmp / "ipc")
    log = (tmp / "mpv.log").open("w+")
    parent = subprocess.Popen([
        shutil.which("mpv"), f"--config-dir={ROOT / 'Resources/mpv'}", "--load-scripts=no",
        f"--script={ROOT / 'Resources/mpv/scripts/thumbfast.lua'}",
        "--script-opts=thumbfast-quit_after_inactivity=1,thumbfast-spawn_first=yes,thumbfast-mpv_path=" + shutil.which("mpv"),
        "--vo=null", "--ao=null", "--pause", "--idle=yes", f"--input-ipc-server={ipc_path}", url,
    ], stdout=log, stderr=log)
    ipc = socket.socket(socket.AF_UNIX)
    try:
        wait_for(lambda: Path(ipc_path).exists())
        ipc.connect(ipc_path)

        def command(*args):
            ipc.sendall((json.dumps({"command": args}) + "\n").encode())

        def thumb(at):
            command("script-message-to", "thumbfast", "thumb", str(at), "10", "10")

        def children():
            result = subprocess.run(["pgrep", "-P", str(parent.pid)], capture_output=True, text=True)
            return result.stdout.split()

        def image():
            files = glob.glob(f"/tmp/thumbfast.out{parent.pid}-*.bgra")
            if not files:
                return None
            data = Path(files[0]).read_bytes()
            return (files[0], hashlib.sha256(data).hexdigest()) if len(data) == 256 * 144 * 4 else None

        # Warm mode opens the worker and produces a preview before any hover.
        first = wait_for(image, timeout=20)
        assert len(children()) == 1, "worker should be running before first hover"
        thumb(1)
        first_hover = wait_for(lambda: (img := image()) and img[1] != first[1] and img)
        for at in range(2, 10):
            thumb(at)
        second = wait_for(lambda: (img := image()) and img[1] != first_hover[1] and img)
        print("PASS: worker stream and initial frame are warm before hover; seeks remain coalesced")
        owned = children()
        assert len(owned) == 1
        os.kill(int(owned[0]), signal.SIGKILL)
        recovered = wait_for(lambda: (img := image()) and img[0] != second[0] and img)
        print("PASS: killed worker recovers without pointer movement")

        command("script-message-to", "thumbfast", "clear")
        wait_for(lambda: not image())
        thumb(3)
        restarted = wait_for(image)
        assert restarted[0] != recovered[0]
        print("PASS: inactivity shutdown/restart then warm re-spawn")
        command("loadfile", url, "replace")
        replaced = wait_for(lambda: (img := image()) and img[0] != restarted[0] and img, timeout=20)
        assert len(children()) == 1, "replacement file should have one warmed worker"
        print("PASS: file replacement prewarms a fresh worker" )
        owned = children()
        assert len(owned) == 1
        os.kill(int(owned[0]), signal.SIGSTOP)
        thumb(8)
        wait_for(lambda: (img := image()) and img[0] != replaced[0], timeout=28)
        print("PASS: stalled worker times out and recovers")
        command("quit")
        parent.wait(timeout=5)
        wait_for(lambda: not glob.glob(f"/tmp/thumbfast*{parent.pid}-*"))
        print("PASS: shutdown cleans temporary files")
    except BaseException:
        log.flush(); log.seek(0); print(log.read())
        raise
    finally:
        ipc.close()
        if parent.poll() is None:
            parent.terminate(); parent.wait(timeout=5)
        server.shutdown()
        log.close()
