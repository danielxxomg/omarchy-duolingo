#!/usr/bin/env python3
"""Contract tests: helper output must satisfy the QML consumer contract.

Regression for the v1.5.0 break: fetch-duo.py emits normalized JSON but
Model.parseUserData expected the raw {users: [...]} shape, so every fetch
was reported invalid ("User not found") even with a configured username.

RED phase: these tests encode the agreed contract before the fix.
Run: python3 -m unittest tests.test_contract -v
"""
import importlib.util
import json
import unittest
import os
import sys

BIN_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


fetch_mod = load("fetch_duo", os.path.join(BIN_DIR, "fetch-duo.py"))

UPSTREAM = json.dumps({"users": [{
    "username": "emma_learn",
    "streak": 12,
    "streak_extended_today": True,
    "totalXp": 5000,
    "name": "Emma Learns",
    "picture": "//img.example/u.png",
    "courses": [
        {"title": "Spanish", "learningLanguage": "es", "xp": 4000, "crowns": 20},
        {"title": "Japanese", "learningLanguage": "ja", "xp": 1000, "crowns": 5},
    ],
}]}).encode()


class TestQmlContract(unittest.TestCase):
    def setUp(self):
        self.doc = fetch_mod.normalize(UPSTREAM)
        self.assertIsNotNone(self.doc)

    # Fields the QML reads and must never lose again.
    def test_has_fullname(self):
        # Privacy: display name is never projected; username doubles as title.
        self.assertEqual(self.doc["fullname"], "emma_learn")

    def test_legal_name_never_projected(self):
        self.assertNotIn("Emma Learns", json.dumps(self.doc))
        self.assertNotIn("name", self.doc)

    def test_has_avatar_https_url(self):
        self.assertEqual(self.doc["avatar"], "https://img.example/u.png")

    def test_course_has_flag(self):
        self.assertEqual(self.doc["courses"][0]["flag"], "\U0001F1EA\U0001F1F8")  # 🇪🇸

    def test_course_fraction_computed(self):
        es = self.doc["courses"][0]
        ja = self.doc["courses"][1]
        self.assertEqual(es["fraction"], 1.0)
        self.assertAlmostEqual(ja["fraction"], 0.25)

    def test_courses_sorted_desc(self):
        self.assertEqual(self.doc["courses"][0]["learningLanguage"], "es")

    def test_top_course_is_first(self):
        self.assertEqual(self.doc["topCourse"]["learningLanguage"], "es")

    def test_output_bytes_are_bounded(self):
        self.assertLess(len(json.dumps(self.doc)), 4096)

    def test_avatar_missing_becomes_empty(self):
        raw = json.loads(UPSTREAM.decode())
        raw["users"][0]["picture"] = ""
        doc = fetch_mod.normalize(json.dumps(raw).encode())
        self.assertEqual(doc["avatar"], "")

    def test_fullname_is_username_regardless_of_upstream(self):
        raw = json.loads(UPSTREAM.decode())
        del raw["users"][0]["name"]
        doc = fetch_mod.normalize(json.dumps(raw).encode())
        self.assertEqual(doc["fullname"], "emma_learn")

    def test_malicious_name_never_leaks(self):
        raw = json.loads(UPSTREAM.decode())
        raw["users"][0]["name"] = "x" * 500
        doc = fetch_mod.normalize(json.dumps(raw).encode())
        self.assertNotIn("x" * 100, json.dumps(doc))


if __name__ == "__main__":
    unittest.main()
