"""Tests for src/server.py (the macOS/Linux helper). Standard library only.

Run with:  python3 -m unittest discover -s tests -p "test_*.py" -v
"""
from __future__ import annotations

import http.client
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "src" / "server.py"
FIXTURES = ROOT / "tests" / "fixtures" / "espanso"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="esm-test-"))
        self.config = self.tmp / "espanso"
        shutil.copytree(FIXTURES, self.config)
        self.backups = self.tmp / "backups"
        self.port = free_port()
        self.proc = subprocess.Popen(
            [sys.executable, str(SERVER), "--no-browser", "--port", str(self.port),
             "--config-dir", str(self.config), "--backup-dir", str(self.backups)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        for _ in range(100):
            try:
                self.request("GET", "/api/ping")
                break
            except OSError:
                time.sleep(0.05)
        else:
            self.fail("server did not start")

    def tearDown(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        if self.proc.stdout:
            self.proc.stdout.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    # ------------------------------------------------------------ helpers
    def request(self, method, path, body=None, headers=None, host=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        h = {"Host": host or f"localhost:{self.port}"}
        if method != "GET":
            h["X-Editor"] = "1"
        h.update(headers or {})
        data = body.encode("utf-8") if isinstance(body, str) else body
        conn.request(method, path, body=data, headers=h)
        r = conn.getresponse()
        raw = r.read()
        conn.close()
        try:
            payload = json.loads(raw.decode("utf-8"))
        except ValueError:
            payload = raw.decode("utf-8", "replace")
        return r.status, payload

    def files(self):
        status, body = self.request("GET", "/api/files")
        self.assertEqual(status, 200)
        return {f["name"]: f for f in body["files"]}

    # ------------------------------------------------------------ tests
    def test_ping_and_status(self):
        self.assertEqual(self.request("GET", "/api/ping"), (200, {"app": "espanso-snippets-manager"}))
        status, body = self.request("GET", "/api/status")
        self.assertEqual(status, 200)
        self.assertIn("running", body)
        self.assertEqual(Path(body["matchDir"]), self.config / "match")

    def test_lists_files_recursively_but_hides_packages(self):
        names = set(self.files())
        self.assertEqual(names, {"base.yml", "work.yml", "work/email.yml", "_private.yml"})

    def test_reads_utf8(self):
        work = self.files()["work.yml"]
        self.assertIn("¯\\\\_(ツ)_/¯", work["text"])
        self.assertIn("café", work["text"])

    def test_save_roundtrip_with_backup(self):
        f = self.files()["work.yml"]
        new = "matches:\n  - trigger: ':x'\n    replace: ✓ ok\n"
        status, body = self.request("PUT", "/api/file?name=work.yml", new, {"X-Expected-Mtime": str(f["mtime"])})
        self.assertEqual(status, 200, body)
        self.assertEqual((self.config / "match" / "work.yml").read_text(encoding="utf-8"), new)
        backups = list(self.backups.glob("work.yml.*.bak"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(encoding="utf-8"), f["text"])

    def test_save_in_subfolder(self):
        f = self.files()["work/email.yml"]
        status, _ = self.request("PUT", "/api/file?name=work%2Femail.yml", "matches: []\n",
                                 {"X-Expected-Mtime": str(f["mtime"])})
        self.assertEqual(status, 200)
        self.assertTrue(list(self.backups.glob("work__email.yml.*.bak")))

    def test_conflict_when_changed_on_disk(self):
        status, body = self.request("PUT", "/api/file?name=work.yml", "matches: []\n", {"X-Expected-Mtime": "1"})
        self.assertEqual(status, 409)
        self.assertEqual(body["error"], "changed")
        self.assertIn(":sig", body["text"])
        status, _ = self.request("PUT", "/api/file?name=work.yml", "matches: []\n", {"X-Expected-Mtime": "1", "X-Force": "1"})
        self.assertEqual(status, 200)

    def test_create_new_file(self):
        status, _ = self.request("PUT", "/api/file?name=personal%2Fhome.yml", "matches: []\n", {"X-Create": "1"})
        self.assertEqual(status, 200)
        self.assertTrue((self.config / "match" / "personal" / "home.yml").is_file())
        status, body = self.request("PUT", "/api/file?name=personal%2Fhome.yml", "matches: []\n", {"X-Create": "1"})
        self.assertEqual((status, body["error"]), (409, "exists"))

    def test_put_to_missing_file_without_create_is_404(self):
        status, _ = self.request("PUT", "/api/file?name=nope.yml", "matches: []\n")
        self.assertEqual(status, 404)

    def test_rejects_bad_names(self):
        for name in ["../escape.yml", "..%2Fescape.yml", "notyaml.txt", "packages%2Fdemo%2Fpackage.yml",
                     "a%2F..%2F..%2Fb.yml", "%2Fetc%2Fpasswd.yml", "we%3Bird.yml", ""]:
            status, _ = self.request("PUT", f"/api/file?name={name}", "matches: []\n", {"X-Create": "1"})
            self.assertEqual(status, 400, name)
        self.assertFalse((self.tmp / "escape.yml").exists())

    def test_rejects_foreign_host(self):
        status, _ = self.request("GET", "/api/files", host="evil.example:80")
        self.assertEqual(status, 403)

    def test_requires_custom_header_for_writes(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.request("PUT", "/api/file?name=work.yml", body=b"matches: []\n", headers={"Host": f"localhost:{self.port}"})
        self.assertEqual(conn.getresponse().status, 403)
        conn.close()

    def test_backups_are_pruned(self):
        path = self.config / "match" / "work.yml"
        for i in range(35):
            mtime = str(int(path.stat().st_mtime * 1000))
            status, _ = self.request("PUT", "/api/file?name=work.yml", f"matches: []\n# {i}\n", {"X-Expected-Mtime": mtime})
            self.assertEqual(status, 200)
        self.assertEqual(len(list(self.backups.glob("work.yml.*.bak"))), 30)

    def test_quit_stops_server(self):
        status, _ = self.request("POST", "/api/quit")
        self.assertEqual(status, 200)
        self.proc.wait(timeout=10)
        self.assertEqual(self.proc.returncode, 0)

    def test_activity_cancels_quit(self):
        self.request("POST", "/api/quit")
        time.sleep(1)
        self.request("GET", "/api/ping")
        time.sleep(4)
        self.assertIsNone(self.proc.poll(), "server should keep running after new activity")


class ConfigDiscoveryTest(unittest.TestCase):
    def test_print_config_uses_explicit_dir(self):
        out = subprocess.run([sys.executable, str(SERVER), "--print-config", "--config-dir", str(FIXTURES)],
                             capture_output=True, text=True, check=True)
        cfg = json.loads(out.stdout)
        self.assertEqual(Path(cfg["match"]), FIXTURES / "match")

    def test_env_variable(self):
        env = dict(os.environ, ESPANSO_CONFIG_DIR=str(FIXTURES))
        out = subprocess.run([sys.executable, str(SERVER), "--print-config"], capture_output=True, text=True, check=True, env=env)
        self.assertEqual(Path(json.loads(out.stdout)["config"]), FIXTURES)


if __name__ == "__main__":
    unittest.main()
