#!/usr/bin/env python3
"""Tests for detect-user.py hardening (marketplace review finding #2).

TDD RED phase. Run: python3 -m unittest tests.test_detect_user -v
"""
import base64
import gzip
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time
import unittest

BIN_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin")


def load_detect_module():
    spec = importlib.util.spec_from_file_location(
        "detect_user", os.path.join(BIN_DIR, "detect-user.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_record(payload_obj):
    """Build a synthetic LevelDB blob: quoted base64 gzip record (mtime=0)."""
    raw = json.dumps(payload_obj).encode("utf-8")
    gz = gzip.compress(raw, mtime=0)
    return b'"' + base64.b64encode(gz) + b'"'


VALID_USER = {"state": {"redux": {"user": {"username": "emma_learn"}}}}


class DetectUserTestBase(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="duo-detect-")
        self.mod = load_detect_module()

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def write(self, name, data):
        path = os.path.join(self.dir, name)
        with open(path, "wb") as fh:
            fh.write(data)
        return path


class TestExtraction(DetectUserTestBase):
    def test_extracts_username_from_synthetic_leveldb(self):
        path = self.write("store", make_record(VALID_USER))
        self.assertEqual(self.mod.find_username([path]), "emma_learn")

    def test_redux_as_json_string_still_works(self):
        inner = json.dumps({"user": {"username": "string_redux"}})
        payload = {"state": {"redux": inner}}
        path = self.write("store", make_record(payload))
        self.assertEqual(self.mod.find_username([path]), "string_redux")

    def test_no_match_returns_empty(self):
        path = self.write("store", b"no duolingo data here")
        self.assertEqual(self.mod.find_username([path]), "")

    def test_truncated_gzip_rejected(self):
        gz = gzip.compress(json.dumps(VALID_USER).encode(), mtime=0)
        cut = base64.b64encode(gz[: len(gz) // 2])
        path = self.write("store", b'"' + cut + b'"')
        self.assertEqual(self.mod.find_username([path]), "")

    def test_invalid_b64_rejected(self):
        path = self.write("store", b'"H4sIAAAAA!!!not-base64!!!"')
        self.assertEqual(self.mod.find_username([path]), "")

    def test_wal_binary_non_ascii_chunking_safely_ignored(self):
        # Corrupted/chunked WAL match containing binary non-ASCII bytes followed by a valid record
        corrupt = b'"H4sIAAAAA\x80\xff\x00some_binary_garbage"'
        valid = make_record(VALID_USER)
        path = self.write("store_wal", corrupt + b"\n" + valid)
        self.assertEqual(self.mod.find_username([path]), "emma_learn")

    def test_sqlite_extraction_success(self):
        import sqlite3
        path = os.path.join(self.dir, "test_data.sqlite")
        conn = sqlite3.connect(path)
        cur = conn.cursor()
        cur.execute("CREATE TABLE data (key TEXT, value BLOB)")
        cur.execute("INSERT INTO data VALUES (?, ?)", ("duo.state", make_record(VALID_USER)))
        conn.commit()
        conn.close()
        self.assertEqual(self.mod.find_username([path]), "emma_learn")

    def test_candidate_paths_include_edge_and_ice(self):
        joined = " ".join(self.mod.CANDIDATE_PATHS)
        self.assertIn("microsoft-edge", joined)
        self.assertIn("ice/firefox", joined)

    def test_leveldb_wal_chunked_blocks_reconstructed(self):
        import hashlib, struct
        incompressible = b"".join([hashlib.sha256(str(i).encode()).digest() for i in range(2500)]).hex()
        user_dict = {
            "state": {
                "redux": {
                    "user": {"username": "emma_learn"},
                    "pad": incompressible
                }
            }
        }
        raw = json.dumps(user_dict).encode("utf-8")
        compressed = gzip.compress(raw)
        b64 = base64.b64encode(compressed).decode("ascii")
        rec = ('"' + b64 + '"').encode("latin-1")
        self.assertGreater(len(rec), 70000)

        block_size = 32768
        header_size = 7
        payload_per_block = block_size - header_size
        chunks = [rec[i:i + payload_per_block] for i in range(0, len(rec), payload_per_block)]
        blocks = []
        for idx, c in enumerate(chunks):
            rec_type = 2 if idx == 0 else (4 if idx == len(chunks) - 1 else 3)
            hdr = struct.pack("<IHb", 0, len(c), rec_type)
            blk = hdr + c
            blk += b"\x00" * (block_size - len(blk))
            blocks.append(blk)
        path = self.write("test_chunked.log", b"".join(blocks))
        self.assertEqual(self.mod.find_username([path]), "emma_learn")


class TestRefusals(DetectUserTestBase):
    def test_symlink_skipped(self):
        real = self.write("real", make_record(VALID_USER))
        link = os.path.join(self.dir, "link")
        os.symlink(real, link)
        self.assertEqual(self.mod.find_username([link]), "")

    def test_fifo_skipped_without_hanging(self):
        fifo = os.path.join(self.dir, "fifo")
        os.mkfifo(fifo)
        start = time.monotonic()
        self.assertEqual(self.mod.find_username([fifo]), "")
        self.assertLess(time.monotonic() - start, 5.0)

    def test_directory_skipped(self):
        self.assertEqual(self.mod.find_username([self.dir]), "")

    def test_missing_file_skipped(self):
        self.assertEqual(
            self.mod.find_username([os.path.join(self.dir, "nope")]), "")


class TestLimits(DetectUserTestBase):
    def test_decompression_bomb_rejected(self):
        bomb = base64.b64encode(
            gzip.compress(b"\x00" * (32 * 1024 * 1024), mtime=0))
        path = self.write("bomb", b'"' + bomb + b'"')
        start = time.monotonic()
        self.assertEqual(self.mod.find_username([path]), "")
        self.assertLess(time.monotonic() - start, 10.0)

    def test_match_cardinality_capped(self):
        self.mod.MAX_MATCHES_PER_FILE = 2
        filler = make_record({"state": {"redux": {}}})
        valid = make_record(VALID_USER)
        content = (b'"' + b'x' * 10 + b'"') * 0  # no-op guard
        path = self.write("many", filler + b"\n" + filler + b"\n" + valid)
        self.assertEqual(self.mod.find_username([path]), "")

    def test_valid_match_within_cardinality_found(self):
        self.mod.MAX_MATCHES_PER_FILE = 3
        filler = make_record({"state": {"redux": {}}})
        valid = make_record(VALID_USER)
        path = self.write("few", filler + b"\n" + valid)
        self.assertEqual(self.mod.find_username([path]), "emma_learn")

    def test_total_budget_cap_aborts_scan(self):
        self.mod.MAX_TOTAL_BYTES = 16
        big = self.write("big", b"z" * 64)
        self.write("valid", make_record(VALID_USER))
        self.assertEqual(self.mod.find_username([big, os.path.join(self.dir, "valid")]), "")

    def test_oversized_single_file_skipped(self):
        self.mod.MAX_FILE_SIZE = 16
        big = self.write("big", b"z" * 64)
        self.assertEqual(self.mod.find_username([big]), "")

    def test_expired_deadline_returns_empty(self):
        self.write("valid", make_record(VALID_USER))
        self.assertEqual(
            self.mod.find_username([os.path.join(self.dir, "valid")],
                                   deadline=time.monotonic() - 1),
            "")


if __name__ == "__main__":
    unittest.main()