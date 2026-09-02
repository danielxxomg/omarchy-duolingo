#!/usr/bin/env python3
"""Tests for fetch-duo.py hardening (marketplace review finding #3).

TDD RED phase. Run: python3 -m unittest tests.test_fetch_duo -v
"""
import importlib.util
import io
import json
import os
import shutil
import stat
import time
import tempfile
import unittest
from unittest import mock

BIN_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin")


def load_fetch_module():
    spec = importlib.util.spec_from_file_location(
        "fetch_duo", os.path.join(BIN_DIR, "fetch-duo.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


VALID_USERS = [{
    "username": "emma_learn",
    "streak": 12,
    "streak_extended_today": True,
    "topLanguage": "Spanish",
    "totalXp": 5000,
    "courses": [{"title": "Spanish", "learningLanguage": "es",
                 "xp": 4000, "crowns": 20}],
}]


class FetchDuoTestBase(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="duo-fetch-")
        self.mod = load_fetch_module()
        self.cache_dir = os.path.join(self.dir, "state")
        self.cache_file = os.path.join(self.cache_dir, "duolingo-cache.json")
        self.mod.CACHE_DIR = self.cache_dir
        self.mod.CACHE_FILE = self.cache_file

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    @staticmethod
    def body(users):
        return json.dumps({"users": users}).encode("utf-8")

    @staticmethod
    def fake_response(data):
        resp = io.BytesIO(data)
        return resp


class TestFetch(DetchBase_placeholder if False else FetchDuoTestBase):
    def test_emits_normalized_schema(self):
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(VALID_USERS))):
            out, code = self.mod.fetch("emma_learn", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertTrue(data["valid"])
        self.assertEqual(data["username"], "emma_learn")
        self.assertEqual(data["streak"], 12)
        self.assertEqual(data["streakExtendedToday"], True)
        self.assertEqual(data["courses"][0]["learningLanguage"], "es")
        self.assertNotIn("users", data)
        self.assertNotIn("picture", data)

class TestRefusals(FetchDuoTestBase):
    def test_error_shape_on_transport_failure(self):
        with mock.patch.object(self.mod.urllib.request, "urlopen", side_effect=OSError("boom")):
            out, code = self.mod.fetch("emma_learn", deadline=time.monotonic() + 10)
        self.assertEqual(code, 1)
        data = json.loads(out)
        self.assertFalse(data["valid"])
        self.assertIn("error", data)
        self.assertNotIn("users", data)

    def test_404_maps_to_user_not_found(self):
        import urllib.error
        err = urllib.error.HTTPError("u", 404, "Not Found", {}, io.BytesIO(b"{}"))
        with mock.patch.object(self.mod.urllib.request, "urlopen", side_effect=err):
            out, code = self.mod.fetch("emma_learn", deadline=time.monotonic() + 10)
        data = json.loads(out)
        self.assertEqual(code, 1)
        self.assertFalse(data["valid"])
        self.assertIn("not found", data["error"].lower())

    def test_response_over_cap_rejected(self):
        big = json.dumps({"users": [], "pad": "x" * (self.mod.MAX_RESPONSE_BYTES + 8)})
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(big.encode())):
            out, code = self.mod.fetch("x", deadline=time.monotonic() + 10)
        self.assertEqual(code, 1)
        self.assertFalse(json.loads(out)["valid"])

    def test_schema_rejects_empty_users(self):
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body([]))):
            out, code = self.mod.fetch("x", deadline=time.monotonic() + 10)
        self.assertFalse(json.loads(out)["valid"])

    def test_schema_rejects_non_dict(self):
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(b"[1,2]")):
            out, code = self.mod.fetch("x", deadline=time.monotonic() + 10)
        self.assertFalse(json.loads(out)["valid"])

    def test_schema_rejects_garbage(self):
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(b"not json")):
            out, code = self.mod.fetch("x", deadline=time.monotonic() + 10)
        self.assertFalse(json.loads(out)["valid"])

    def test_string_lengths_capped(self):
        users = [{"username": "u" * 300, "streak": 1, "totalXp": 1, "courses": []}]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users))):
            out, code = self.mod.fetch("x", deadline=time.monotonic() + 10)
        self.assertFalse(json.loads(out)["valid"])

    def test_courses_cardinality_capped(self):
        users = [{
            "username": "ok_user", "streak": 1, "totalXp": 1,
            "courses": [{"title": "L%d" % i, "learningLanguage": "zz",
                         "xp": i, "crowns": 0} for i in range(60)],
        }]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users))):
            out, code = self.mod.fetch("x", deadline=time.monotonic() + 10)
        self.assertFalse(json.loads(out)["valid"])

    def test_no_username_falls_back_to_cache(self):
        os.makedirs(self.cache_dir, exist_ok=True)
        with open(self.cache_file, "w") as fh:
            fh.write(json.dumps({"valid": True, "username": "cached_user", "streak": 3}))
        out, code = self.mod.fetch("", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["username"], "cached_user")

    def test_cache_write_is_0600(self):
        os.makedirs(self.cache_dir, exist_ok=True)
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(VALID_USERS))):
            self.mod.fetch("emma_learn", deadline=time.monotonic() + 10)
        self.assertEqual(stat.S_IMODE(os.stat(self.cache_file).st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
