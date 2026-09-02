#!/usr/bin/env python3
"""Black-box tests for state-io.py (review findings #4 and #5).

TDD: written with the implementation as an executable contract check;
exercises the real CLI over subprocess with payloads on stdin.
"""
import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "bin", "state-io.py")


class StateIoTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="duo-state-")
        os.chmod(self.dir, 0o700)
        self.env = dict(os.environ, DUO_STATE_DIR=self.dir)

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def run_io(self, *args, stdin=None):
        return subprocess.run(
            ["python3", BIN, *args],
            capture_output=True, env=self.env, timeout=15,
            input=stdin)

    def test_read_missing_state_exits_zero_empty(self):
        result = self.run_io("read")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_write_then_read_roundtrip(self):
        payload = json.dumps({"rev": 4, "days": {"2026-09-01": {"streak": 3}}})
        result = self.run_io("write", "4", stdin=payload.encode())
        self.assertEqual(result.returncode, 0, result.stderr)
        path = os.path.join(self.dir, "history.json")
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        readback = self.run_io("read")
        self.assertEqual(json.loads(readback.stdout), json.loads(payload))

    def test_write_rejects_stale_rev(self):
        self.run_io("write", "5", stdin=b'{"rev":5}')
        result = self.run_io("write", "5", stdin=b'{"rev":5}')
        self.assertEqual(result.returncode, 3)

    def test_write_accepts_newer_rev(self):
        self.run_io("write", "5", stdin=b'{"rev":5}')
        result = self.run_io("write", "6", stdin=b'{"rev":6}')
        self.assertEqual(result.returncode, 0)

    def test_write_rejects_over_cap(self):
        big = json.dumps({"rev": 1, "pad": "x" * (300 * 1024)})
        result = self.run_io("write", "1", stdin=big.encode())
        self.assertEqual(result.returncode, 2)

    def test_write_refuses_symlink_target(self):
        outside = tempfile.mkdtemp(prefix="duo-outside-")
        victim = os.path.join(outside, "victim.txt")
        with open(victim, "w") as fh:
            fh.write("do not touch")
        os.symlink(victim, os.path.join(self.dir, "history.json"))
        result = self.run_io("write", "1", stdin=b'{"rev":1}')
        self.assertEqual(result.returncode, 1)
        with open(victim) as fh:
            self.assertEqual(fh.read(), "do not touch")
        shutil.rmtree(outside, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
