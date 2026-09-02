#!/usr/bin/env python3
"""Tests for duoio.py hardened persistence helpers.

TDD RED phase: written before implementation exists.
Run: python3 -m unittest tests.test_duoio -v
"""
import os
import shutil
import stat
import sys
import tempfile
import unittest

BIN_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin")
sys.path.insert(0, BIN_DIR)

import duoio  # noqa: E402


class TestOpenRegularNoFollow(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="duoio-test-")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_opens_regular_file(self):
        path = os.path.join(self.dir, "f")
        with open(path, "wb") as fh:
            fh.write(b"ok")
        fd = duoio.open_regular_nofollow(path)
        try:
            self.assertIsInstance(fd, int)
            self.assertGreaterEqual(fd, 0)
        finally:
            os.close(fd)

    def test_rejects_symlink(self):
        target = os.path.join(self.dir, "real")
        with open(target, "wb") as fh:
            fh.write(b"secret")
        link = os.path.join(self.dir, "link")
        os.symlink(target, link)
        with self.assertRaises(duoio.DuoIOError):
            duoio.open_regular_nofollow(link)

    def test_rejects_fifo(self):
        fifo = os.path.join(self.dir, "fifo")
        os.mkfifo(fifo)
        with self.assertRaises(duoio.DuoIOError):
            duoio.open_regular_nofollow(fifo)

    def test_rejects_directory(self):
        with self.assertRaises(duoio.DuoIOError):
            duoio.open_regular_nofollow(self.dir)

    def test_missing_file_raises(self):
        with self.assertRaises(duoio.DuoIOError):
            duoio.open_regular_nofollow(os.path.join(self.dir, "nope"))

    def test_read_bounded_returns_full_content_up_to_limit(self):
        path = os.path.join(self.dir, "med")
        with open(path, "wb") as fh:
            fh.write(b"x" * 50)
        fd = duoio.open_regular_nofollow(path)
        try:
            self.assertEqual(duoio.read_bounded(fd, 50), b"x" * 50)
        finally:
            os.close(fd)

    def test_read_bounded_over_cap_raises(self):
        path = os.path.join(self.dir, "big")
        with open(path, "wb") as fh:
            fh.truncate(duoio.MAX_READ_BYTES + 1)
        fd = duoio.open_regular_nofollow(path)
        try:
            # file is larger than the limit -> refuse
            with self.assertRaises(duoio.DuoIOError):
                duoio.read_bounded(fd, duoio.MAX_READ_BYTES)
        finally:
            os.close(fd)


class TestAtomicWrite(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="duoio-test-")
        os.chmod(self.dir, 0o700)

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_write_creates_0600_file(self):
        dirfd = os.open(self.dir, os.O_RDONLY | os.O_DIRECTORY)
        try:
            duoio.atomic_write_dirfd(dirfd, "data", max_bytes=64 * 1024)
        finally:
            os.close(dirfd)
        path = os.path.join(self.dir, "duolingo-state.json")
        st = os.stat(path)
        self.assertEqual(stat.S_IMODE(st.st_mode), 0o600)
        with open(path) as fh:
            self.assertEqual(fh.read(), "data")

    def test_write_payload_over_cap_raises(self):
        dirfd = os.open(self.dir, os.O_RDONLY | os.O_DIRECTORY)
        try:
            with self.assertRaises(duoio.DuoIOError):
                duoio.atomic_write_dirfd(dirfd, "x" * (64 * 1024 + 1), max_bytes=64 * 1024)
        finally:
            os.close(dirfd)

    def test_exclusive_refuses_same_or_newer_rev(self):
        dirfd = os.open(self.dir, os.O_RDONLY | os.O_DIRECTORY)
        try:
            duoio.atomic_write_dirfd(dirfd, '{"rev":5}', max_bytes=64 * 1024, expect_rev_less_than=5)
            with self.assertRaises(duoio.RevConflict):
                duoio.atomic_write_dirfd(dirfd, '{"rev":5}', max_bytes=64 * 1024, expect_rev_less_than=5)
            duoio.atomic_write_dirfd(dirfd, '{"rev":6}', max_bytes=64 * 1024, expect_rev_less_than=6)
        finally:
            os.close(dirfd)

    def test_exclusive_allows_first_write(self):
        dirfd = os.open(self.dir, os.O_RDONLY | os.O_DIRECTORY)
        try:
            duoio.atomic_write_dirfd(dirfd, '{"rev":3}', max_bytes=64 * 1024, expect_rev_less_than=3)
        finally:
            os.close(dirfd)
        with open(os.path.join(self.dir, "duolingo-state.json")) as fh:
            self.assertEqual(fh.read(), '{"rev":3}')


if __name__ == "__main__":
    unittest.main()