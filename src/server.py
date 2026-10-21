#!/usr/bin/env python3
"""Espanso Snippets Manager - local helper (macOS, Linux; also works on Windows).

Serves the editor page and reads/writes the .yml files in Espanso's match
folder. It only listens on 127.0.0.1 and stops when the editor window closes.
Requires Python 3.8+ and nothing else.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

APP_ID = "espanso-snippets-manager"
DEFAULT_PORT = 47811
PORT_RANGE = 10
KEEP_BACKUPS = 30
QUIT_GRACE_SECONDS = 4
IDLE_LIMIT_SECONDS = 8 * 3600
HERE = Path(__file__).resolve().parent
SYSTEM = platform.system()  # 'Windows' | 'Darwin' | 'Linux'
SEGMENT = re.compile(r"^[\w\- .]+$")


# --------------------------------------------------------------------------- paths
def _espanso_cli() -> str | None:
    found = shutil.which("espanso")
    if found:
        return found
    candidates = {
        "Darwin": ["/Applications/Espanso.app/Contents/MacOS/espanso", "/opt/homebrew/bin/espanso", "/usr/local/bin/espanso"],
        "Linux": ["/usr/bin/espanso", "/usr/local/bin/espanso", str(Path.home() / ".local/bin/espanso")],
        "Windows": [str(Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Espanso/espanso.cmd")],
    }.get(SYSTEM, [])
    return next((c for c in candidates if Path(c).is_file()), None)


def find_config_dir(explicit: str | None = None) -> Path:
    """Locate Espanso's config folder (the one containing match/)."""
    for value in (explicit, os.environ.get("ESPANSO_CONFIG_DIR")):
        if value:
            return Path(value).expanduser()
    cli = _espanso_cli()
    if cli:
        try:
            out = subprocess.run([cli, "path", "config"], capture_output=True, text=True, timeout=5)
            line = (out.stdout or "").strip().splitlines()
            if line:
                candidate = Path(line[-1].split(":", 1)[-1].strip() if line[-1].lower().startswith("config:") else line[-1].strip())
                if (candidate / "match").is_dir():
                    return candidate
        except (OSError, subprocess.SubprocessError):
            pass
    home = Path.home()
    if SYSTEM == "Windows":
        defaults = [Path(os.environ.get("APPDATA", home / "AppData/Roaming")) / "espanso"]
    elif SYSTEM == "Darwin":
        defaults = [home / "Library/Application Support/espanso", home / "Library/Preferences/espanso"]
    else:
        xdg = os.environ.get("XDG_CONFIG_HOME") or str(home / ".config")
        defaults = [Path(xdg) / "espanso"]
    return next((d for d in defaults if (d / "match").is_dir()), defaults[0])


def default_backup_dir() -> Path:
    home = Path.home()
    if SYSTEM == "Windows":
        return Path(os.environ.get("LOCALAPPDATA", home / "AppData/Local")) / "Espanso Snippets Manager" / "backups"
    if SYSTEM == "Darwin":
        return home / "Library/Application Support/Espanso Snippets Manager/backups"
    state = os.environ.get("XDG_STATE_HOME") or str(home / ".local/state")
    return Path(state) / APP_ID / "backups"


# --------------------------------------------------------------------------- helpers
def mtime_ms(path: Path) -> int:
    return int(path.stat().st_mtime * 1000)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


class Store:
    def __init__(self, config_dir: Path, backup_dir: Path):
        self.config_dir = config_dir
        self.match_dir = config_dir / "match"
        self.backup_dir = backup_dir

    def resolve(self, name: str | None) -> Path:
        """Map a relative name like 'work/email.yml' to a path inside match/."""
        if not name:
            raise ValueError("Missing file name")
        parts = name.replace("\\", "/").split("/")
        if (
            not re.search(r"\.ya?ml$", name, re.I)
            or any(p in ("", ".", "..") or not SEGMENT.match(p) for p in parts)
            or parts[0].lower() == "packages"
        ):
            raise ValueError("Invalid file name")
        path = (self.match_dir / Path(*parts)).resolve()
        if self.match_dir.resolve() not in path.parents:
            raise ValueError("Invalid file name")
        return path

    def list_files(self) -> list[dict]:
        if not self.match_dir.is_dir():
            return []
        out = []
        for path in sorted(self.match_dir.rglob("*")):
            rel = path.relative_to(self.match_dir).as_posix()
            if not path.is_file() or not re.search(r"\.ya?ml$", rel, re.I) or rel.split("/")[0].lower() == "packages":
                continue
            out.append({"name": rel, "mtime": mtime_ms(path), "text": read_text(path)})
        return out

    def backup(self, path: Path, name: str) -> None:
        if not path.exists():
            return
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        flat = name.replace("/", "__")
        stamp = _dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        shutil.copy2(path, self.backup_dir / f"{flat}.{stamp}.bak")
        old = sorted(self.backup_dir.glob(f"{flat}.*.bak"), key=lambda p: p.stat().st_mtime, reverse=True)
        for extra in old[KEEP_BACKUPS:]:
            try:
                extra.unlink()
            except OSError:
                pass

    def write(self, name: str, text: str, expected: str | None, force: bool, create: bool) -> tuple[int, dict]:
        path = self.resolve(name)
        exists = path.exists()
        if create and exists:
            return 409, {"error": "exists"}
        if not create and not exists:
            return 404, {"error": "Not found"}
        if exists and expected and not force and str(mtime_ms(path)) != expected:
            return 409, {"error": "changed", "mtime": mtime_ms(path), "text": read_text(path)}
        path.parent.mkdir(parents=True, exist_ok=True)
        self.backup(path, name)
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_bytes(text.encode("utf-8"))
        os.replace(tmp, path)
        return 200, {"ok": True, "mtime": mtime_ms(path)}


def espanso_running() -> bool:
    try:
        if SYSTEM == "Windows":
            out = subprocess.run(["tasklist"], capture_output=True, text=True, timeout=5).stdout.lower()
            return "espanso" in out
        return subprocess.run(["pgrep", "-x", "espanso"], capture_output=True, timeout=5).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def open_folder(path: Path) -> None:
    if SYSTEM == "Windows":
        os.startfile(str(path))  # type: ignore[attr-defined]  # noqa: S606
    elif SYSTEM == "Darwin":
        subprocess.Popen(["open", str(path)])
    else:
        subprocess.Popen(["xdg-open", str(path)])


def open_ui(url: str) -> None:
    """Open the editor in a chromeless app window when a Chromium browser exists."""
    app_args = [f"--app={url}", "--window-size=1240,800"]
    try:
        if SYSTEM == "Darwin":
            for app in ("Google Chrome", "Microsoft Edge", "Brave Browser", "Chromium"):
                for root in (Path("/Applications"), Path.home() / "Applications"):
                    if (root / f"{app}.app").exists():
                        subprocess.Popen(["open", "-na", str(root / f"{app}.app"), "--args", *app_args])
                        return
        elif SYSTEM == "Linux":
            for exe in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge", "brave-browser"):
                found = shutil.which(exe)
                if found:
                    subprocess.Popen([found, *app_args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    return
        elif SYSTEM == "Windows":
            for base in (os.environ.get("ProgramFiles(x86)"), os.environ.get("ProgramFiles")):
                edge = Path(base or "") / "Microsoft/Edge/Application/msedge.exe"
                if base and edge.is_file():
                    subprocess.Popen([str(edge), *app_args])
                    return
    except OSError:
        pass
    webbrowser.open(url)


# --------------------------------------------------------------------------- server
class State:
    quit_at: float | None = None
    last_hit: float = time.time()


def make_handler(store: Store, port: int, index_html: Path, state: State):
    allowed_hosts = {f"localhost:{port}", f"127.0.0.1:{port}"}

    class Handler(BaseHTTPRequestHandler):
        server_version = "EspansoSnippetsManager"

        def log_message(self, fmt, *args):  # quiet
            if os.environ.get("ESM_DEBUG"):
                super().log_message(fmt, *args)

        # ---- responses
        def _send(self, code: int, ctype: str, body: bytes) -> None:
            self.send_response(code)
            self.send_header("Content-Type", f"{ctype}; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(body)

        def _json(self, code: int, obj) -> None:
            self._send(code, "application/json", json.dumps(obj, ensure_ascii=False).encode("utf-8"))

        # ---- gatekeeping
        def _allowed(self) -> bool:
            if self.headers.get("Host") not in allowed_hosts:
                self._send(403, "text/plain", b"Forbidden")
                return False
            path = urllib.parse.urlparse(self.path).path
            if self.command != "GET" and path != "/api/quit" and self.headers.get("X-Editor") != "1":
                self._send(403, "text/plain", b"Forbidden")
                return False
            state.last_hit = time.time()
            if path != "/api/quit":
                state.quit_at = None
            return True

        def _body(self) -> str:
            length = int(self.headers.get("Content-Length") or 0)
            return self.rfile.read(length).decode("utf-8") if length else ""

        def handle_one_request(self):
            try:
                super().handle_one_request()
            except Exception as err:  # noqa: BLE001 - never drop a request without answering
                try:
                    self._json(500, {"error": str(err)})
                except Exception:  # noqa: BLE001
                    pass

        # ---- routes
        def do_GET(self):  # noqa: N802
            if not self._allowed():
                return
            url = urllib.parse.urlparse(self.path)
            query = urllib.parse.parse_qs(url.query)
            try:
                if url.path == "/":
                    return self._send(200, "text/html", index_html.read_bytes())
                if url.path == "/api/ping":
                    return self._json(200, {"app": APP_ID})
                if url.path == "/api/status":
                    return self._json(200, {"running": espanso_running(), "matchDir": str(store.match_dir),
                                            "backupDir": str(store.backup_dir)})
                if url.path == "/api/files":
                    return self._json(200, {"files": store.list_files()})
                if url.path == "/api/file":
                    path = store.resolve((query.get("name") or [None])[0])
                    if not path.exists():
                        return self._json(404, {"error": "Not found"})
                    return self._json(200, {"name": query["name"][0], "mtime": mtime_ms(path), "text": read_text(path)})
            except ValueError as err:
                return self._json(400, {"error": str(err)})
            self._send(404, "text/plain", b"Not found")

        def do_PUT(self):  # noqa: N802
            if not self._allowed():
                return
            url = urllib.parse.urlparse(self.path)
            if url.path != "/api/file":
                return self._send(404, "text/plain", b"Not found")
            name = (urllib.parse.parse_qs(url.query).get("name") or [None])[0]
            try:
                code, obj = store.write(name or "", self._body(), self.headers.get("X-Expected-Mtime"),
                                        self.headers.get("X-Force") == "1", self.headers.get("X-Create") == "1")
            except ValueError as err:
                code, obj = 400, {"error": str(err)}
            except OSError as err:
                code, obj = 500, {"error": str(err)}
            self._json(code, obj)

        def do_POST(self):  # noqa: N802
            if not self._allowed():
                return
            path = urllib.parse.urlparse(self.path).path
            self._body()
            if path == "/api/quit":
                state.quit_at = time.time() + QUIT_GRACE_SECONDS
                return self._json(200, {"ok": True})
            if path == "/api/openfolder":
                store.match_dir.mkdir(parents=True, exist_ok=True)
                open_folder(store.match_dir)
                return self._json(200, {"ok": True})
            self._send(404, "text/plain", b"Not found")

    return Handler


def already_running(port: int) -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/ping", timeout=1) as r:  # noqa: S310
            return APP_ID in r.read().decode("utf-8", "replace")
    except OSError:
        return False


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Espanso Snippets Manager")
    ap.add_argument("--port", type=int, default=int(os.environ.get("ESM_PORT", DEFAULT_PORT)))
    ap.add_argument("--config-dir", help="Espanso config folder (the one that contains match/)")
    ap.add_argument("--backup-dir", default=os.environ.get("ESM_BACKUP_DIR"))
    ap.add_argument("--no-browser", action="store_true", help="Don't open a window")
    ap.add_argument("--print-config", action="store_true", help="Print the folders that would be used and exit")
    args = ap.parse_args(argv)

    store = Store(find_config_dir(args.config_dir), Path(args.backup_dir) if args.backup_dir else default_backup_dir())
    if args.print_config:
        print(json.dumps({"config": str(store.config_dir), "match": str(store.match_dir), "backups": str(store.backup_dir)}, indent=2))
        return 0

    index_html = HERE / "index.html"
    if not index_html.is_file():
        print(f"index.html not found next to {__file__}", file=sys.stderr)
        return 1

    for port in range(args.port, args.port + PORT_RANGE):
        if already_running(port):
            if not args.no_browser:
                open_ui(f"http://localhost:{port}/")
            return 0
        state = State()
        try:
            httpd = ThreadingHTTPServer(("127.0.0.1", port), make_handler(store, port, index_html, state))
        except OSError:
            continue
        break
    else:
        print("No free port found.", file=sys.stderr)
        return 1

    httpd.daemon_threads = True
    url = f"http://localhost:{port}/"
    print(f"Espanso Snippets Manager running at {url}", flush=True)
    print(f"Match folder: {store.match_dir}", flush=True)

    def watchdog():
        while True:
            time.sleep(1)
            now = time.time()
            if (state.quit_at and now > state.quit_at) or now - state.last_hit > IDLE_LIMIT_SECONDS:
                httpd.shutdown()
                return

    threading.Thread(target=watchdog, daemon=True).start()
    if not args.no_browser:
        threading.Timer(0.2, open_ui, args=(url,)).start()
    try:
        httpd.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
