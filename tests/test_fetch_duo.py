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

    def test_invalid_username_format_returns_error_code_1_no_cache_fallback(self):
        os.makedirs(self.cache_dir, exist_ok=True)
        with open(self.cache_file, "w") as fh:
            fh.write(json.dumps({"valid": True, "username": "cached_user", "streak": 3}))
        for bad_name in ["!", "x", "bad name", "a" * 26]:
            out, code = self.mod.fetch(bad_name, deadline=time.monotonic() + 10)
            self.assertEqual(code, 1)
            data = json.loads(out)
            self.assertFalse(data["valid"])
            self.assertEqual(data["error"], "Invalid username format")

    def test_empty_users_list_returns_user_not_found(self):
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body([]))):
            out, code = self.mod.fetch("valid_user", deadline=time.monotonic() + 10)
        self.assertEqual(code, 1)
        data = json.loads(out)
        self.assertFalse(data["valid"])
        self.assertEqual(data["error"], "User not found on Duolingo")

    def test_courses_truncated_to_max_courses(self):
        users = [{
            "username": "ok_user", "streak": 1, "totalXp": 1,
            "courses": [{"title": "L%d" % i, "learningLanguage": "es",
                         "xp": i, "crowns": 0} for i in range(60)],
        }]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users))):
            out, code = self.mod.fetch("ok_user", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertTrue(data["valid"])
        self.assertEqual(len(data["courses"]), self.mod.MAX_COURSES)

    def test_regional_language_tags_and_flags(self):
        users = [{
            "username": "polyglot", "streak": 5, "totalXp": 1000,
            "courses": [
                {"title": "Dutch", "learningLanguage": "nl-NL", "xp": 500, "crowns": 10},
                {"title": "Chinese", "learningLanguage": "zh-CN", "xp": 300, "crowns": 5},
                {"title": "Spanish (LatAm)", "learningLanguage": "es-419", "xp": 200, "crowns": 2},
                {"title": "Dutch (Alt)", "learningLanguage": "nl_NL", "xp": 150, "crowns": 1},
                {"title": "Chinese (Alt)", "learningLanguage": "zh_CN", "xp": 100, "crowns": 1},
            ],
        }]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users))):
            out, code = self.mod.fetch("polyglot", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertTrue(data["valid"])
        self.assertEqual(data["courses"][0]["flag"], "🇳🇱")
        self.assertEqual(data["courses"][1]["flag"], "🇨🇳")
        self.assertEqual(data["courses"][2]["flag"], "🇪🇸")
        self.assertEqual(data["courses"][3]["flag"], "🇳🇱")
        self.assertEqual(data["courses"][4]["flag"], "🇨🇳")

    def test_long_avatar_url_preserved(self):
        long_avatar = "https://d3gq3s1iyyx31w.cloudfront.net/static/render/bg/BackgroundColor-3/Body-5/ClothingColor-6/Expression-47/EyeColor-1/FacialHair-0/FacialHairColor-1/Glasses-0/GlassesColor-1/Headwear-10/HeadwearColor-6/MainHair-64/MainHairColor-5/Nose%20Piercing-0/Piercings-0/SkinTone-3/Wrinkles-0"
        self.assertGreater(len(long_avatar), 200)
        users = [{
            "username": "avatar_user", "streak": 2, "totalXp": 50,
            "picture": long_avatar, "courses": [],
        }]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users))):
            out, code = self.mod.fetch("avatar_user", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertEqual(data["avatar"], long_avatar)

    def test_has_plus_handling(self):
        # Explicit true
        users_plus = [{"username": "plus_user", "streak": 5, "totalXp": 100, "hasPlus": True, "courses": []}]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users_plus))):
            out, code = self.mod.fetch("plus_user", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        self.assertTrue(json.loads(out)["hasPlus"])

        # Explicit false
        users_free = [{"username": "free_user", "streak": 5, "totalXp": 100, "hasPlus": False, "courses": []}]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users_free))):
            out, code = self.mod.fetch("free_user", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        self.assertFalse(json.loads(out)["hasPlus"])

        # Omitted defaults to false
        users_default = [{"username": "default_user", "streak": 5, "totalXp": 100, "courses": []}]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users_default))):
            out, code = self.mod.fetch("default_user", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        self.assertFalse(json.loads(out)["hasPlus"])

    def test_creation_date_handling(self):
        # Valid integer timestamp
        users_valid = [{
            "username": "old_user", "streak": 1, "totalXp": 10,
            "creationDate": 1612345678, "courses": [],
        }]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users_valid))):
            out, code = self.mod.fetch("old_user", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["creationDate"], 1612345678)

        # Invalid / null / string / bool timestamps become None
        for bad_val in [None, "2021-01-01", True, False, 0, -100]:
            users_bad = [{
                "username": "bad_ts_user", "streak": 1, "totalXp": 10,
                "creationDate": bad_val, "courses": [],
            }]
            with mock.patch.object(self.mod.urllib.request, "urlopen",
                                   return_value=self.fake_response(self.body(users_bad))):
                out, code = self.mod.fetch("bad_ts_user", deadline=time.monotonic() + 10)
            self.assertEqual(code, 0)
            self.assertIsNone(json.loads(out)["creationDate"])

    def test_longest_streak_handling(self):
        # streakData.longestStreak.length present and valid
        users_with_ls = [{
            "username": "streak_king", "streak": 10, "totalXp": 500,
            "streakData": {"longestStreak": {"length": 150}},
            "courses": [],
        }]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users_with_ls))):
            out, code = self.mod.fetch("streak_king", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["longestStreak"], 150)

        # streakData missing longestStreak -> fallback to current streak
        users_fallback = [{
            "username": "streak_fallback", "streak": 22, "totalXp": 500,
            "streakData": {}, "courses": [],
        }]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users_fallback))):
            out, code = self.mod.fetch("streak_fallback", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["longestStreak"], 22)

        # streakData missing entirely -> fallback to current streak
        users_no_streak_data = [{
            "username": "streak_none", "streak": 7, "totalXp": 500,
            "courses": [],
        }]
        with mock.patch.object(self.mod.urllib.request, "urlopen",
                               return_value=self.fake_response(self.body(users_no_streak_data))):
            out, code = self.mod.fetch("streak_none", deadline=time.monotonic() + 10)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["longestStreak"], 7)


if __name__ == "__main__":
    unittest.main()
