#!/usr/bin/env python3
"""Best-effort detection of the local Duolingo username.

Privacy (review #4297 finding #1): runs only when the user explicitly
enables auto-detection; default is opt-in OFF. Reads only CANDIDATE_PATHS
and extracts only the user.username field. Nothing is persisted or sent.

Security (finding #2): descriptor-bound no-follow reads verified regular
via fstat (no TOCTOU swap, no fifo wedge); decompression capped; match
cardinality, per-file size, total budget, and deadline all bounded.
"""
import base64
import glob
import gzip
import io
import json
import os
import re
import sys
import time

from duoio import DuoIOError, open_regular_nofollow

MAX_FILE_SIZE = 16 * 1024 * 1024
MAX_TOTAL_BYTES = 64 * 1024 * 1024
MAX_DECOMPRESSED_BYTES = 4 * 1024 * 1024
MAX_MATCHES_PER_FILE = 64
DEADLINE_SECONDS = 20.0

CANDIDATE_PATHS = [
    "~/.config/DL: language lessons/Local Storage/leveldb/*",
    "~/.config/BraveSoftware/Brave-Browser/Default/Local Storage/leveldb/*",
    "~/.config/google-chrome/Default/Local Storage/leveldb/*",
    "~/.config/chromium/Default/Local Storage/leveldb/*",
]

RECORD_RE = re.compile(r'"(H4sIAAAAA[^"]+)"')
USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{2,25}$")


def find_username(paths=None, deadline=None):
    """Scan candidate LevelDB stores; return the username or empty string."""
    if deadline is None:
        deadline = time.monotonic() + DEADLINE_SECONDS
    total = 0
    for path in _candidate_files(paths):
        if time.monotonic() > deadline:
            return ""
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        if size > MAX_FILE_SIZE:
            continue
        if total + size > MAX_TOTAL_BYTES:
            return ""
        total += size
        username = _extract_from_file(path, deadline)
        if username:
            return username
    return ""


def _candidate_files(paths=None):
    if paths is None:
        paths = CANDIDATE_PATHS
    for pattern in paths:
        for path in glob.glob(os.path.expanduser(pattern)):
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            yield path


def _extract_from_file(path, deadline):
    try:
        fd = open_regular_nofollow(path)
    except DuoIOError:
        return ""
    try:
        with open(fd, "rb", closefd=False) as handle:
            content = handle.read(MAX_FILE_SIZE + 1)
    except OSError:
        return ""
    finally:
        os.close(fd)
    if len(content) > MAX_FILE_SIZE:
        return ""  # grew past cap between stat and read: refuse
    return _extract_from_content(content, deadline)


def _extract_from_content(content, deadline):
    text = content.decode("latin-1", errors="ignore")
    matches = RECORD_RE.findall(text)
    if len(matches) > MAX_MATCHES_PER_FILE:
        matches = matches[:MAX_MATCHES_PER_FILE]
    for encoded in matches:
        if time.monotonic() > deadline:
            return ""
        username = _decode_candidate(encoded)
        if username:
            return username
    return ""


def _decode_candidate(encoded):
    """Decode one base64-gzip record under hard expansion caps."""
    try:
        compressed = base64.b64decode(encoded + "=" * (-len(encoded) % 4),
                                      validate=True)
    except (ValueError, TypeError):
        return ""
    try:
        gunzip = gzip.GzipFile(fileobj=io.BytesIO(compressed))
        chunks = []
        got = 0
        while True:
            chunk = gunzip.read(65536)
            if not chunk:
                break
            got += len(chunk)
            if got > MAX_DECOMPRESSED_BYTES:
                return ""
            chunks.append(chunk)
        raw = b"".join(chunks)
    except (OSError, EOFError):
        return ""
    try:
        data = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return ""
    redux = data.get("state", {}).get("redux", {})
    if isinstance(redux, str):
        try:
            redux = json.loads(redux)
        except ValueError:
            return ""
    if not isinstance(redux, dict):
        return ""
    user = redux.get("user")
    if not isinstance(user, dict):
        return ""
    name = user.get("username")
    if isinstance(name, str):
        name = name.strip()
        if USERNAME_RE.match(name):
            return name
    return ""


def main():
    try:
        user = find_username()
    except BaseException:
        user = ""
    if user:
        print(user)
        sys.exit(0)
    sys.exit(1)


if __name__ == "__main__":
    main()