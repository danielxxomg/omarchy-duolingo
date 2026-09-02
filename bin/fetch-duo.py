#!/usr/bin/env python3
"""Fetch Duolingo user stats and emit a normalized, bounded JSON document.

Security contract (marketplace review #4297, finding #3):
- The HTTP response is streamed under a hard byte ceiling (no unbounded
  resp.read()) with a producer deadline.
- The response is schema-validated (object, users[0] dict, field types,
  string length and course cardinality caps) before emission.
- Only a small normalized document is emitted and cached — never the raw
  upstream blob — so the QML side never buffers attacker-sized stdout.
- Cache writes are exclusive 0600 atomic renames anchored to a pinned
  directory fd (duoio); cache reads are descriptor-bound, no-follow, and
  size-capped.
"""
import io
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from duoio import (  # noqa: E402
    DuoIOError,
    atomic_write_dirfd,
    open_regular_nofollow,
    read_bounded,
)

CACHE_DIR = os.path.expanduser("~/.local/state/duolingo")
CACHE_NAME = "duolingo-cache.json"
MAX_RESPONSE_BYTES = 1 * 1024 * 1024
MAX_READ_CHUNK = 65536
HTTP_TIMEOUT = 7.0
MAX_MATCHES = 1
MAX_COURSES = 50
MAX_STR = 120
MAX_STR_LONG = 80

USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{2,25}$")

# Same emoji table as Model.js FLAG_MAP, kept in sync for helper-side flags.
FLAG_MAP = {
    "en": "🇬🇧", "es": "🇪🇸", "fr": "🇫🇷", "de": "🇩🇪", "it": "🇮🇹",
    "pt": "🇧🇷", "ja": "🇯🇵", "zh": "🇨🇳", "ko": "🇰🇷", "ru": "🇷🇺",
    "nl": "🇳🇱", "pl": "🇵🇱", "sv": "🇸🇪", "el": "🇬🇷", "tr": "🇹🇷",
    "uk": "🇺🇦", "vi": "🇻🇳", "ar": "🇸🇦", "hi": "🇮🇳", "eo": "🟢",
    "la": "🏛️", "he": "🇮🇱", "ga": "🇮🇪", "da": "🇩🇰", "no": "🇳🇴",
    "fi": "🇫🇮", "cs": "🇨🇿", "ro": "🇷🇴", "hu": "🇭🇺", "id": "🇮🇩",
    "th": "🇹🇭",
}


def fetch(username, deadline=None):
    """Return (stdout_text, exit_code). Normalized JSON only."""
    if deadline is None:
        deadline = time.monotonic() + HTTP_TIMEOUT + 1.0
    if username:
        try:
            body = _http_fetch(username, deadline)
        except UpstreamError as exc:
            return json.dumps({"valid": False, "error": str(exc)}), 1
        if body is not None:
            data = normalize(body)
            if data is not None:
                _cache_write(json.dumps(data))
                return json.dumps(data), 0
            # Unparseable/oversized response from upstream: hard error.
            return json.dumps({"valid": False,
                               "error": "Invalid Duolingo response"}), 1
        # Transport failure: fall back to cache if present.
        cached = _cache_read()
        if cached is not None:
            return json.dumps(cached), 0
        return json.dumps({"valid": False,
                           "error": "Network error fetching Duolingo data"}), 1
    # No username: serve cache if present.
    cached = _cache_read()
    if cached is not None:
        return json.dumps(cached), 0
    return json.dumps({"valid": False,
                       "error": "No username provided or detected"}), 1


def _http_fetch(username, deadline):
    url = ("https://www.duolingo.com/2017-06-30/users?username="
           + urllib.parse.quote(username, safe=""))
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    })
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            chunks = []
            got = 0
            while True:
                if time.monotonic() > deadline:
                    return None
                chunk = resp.read(MAX_READ_CHUNK)
                if not chunk:
                    break
                got += len(chunk)
                if got > MAX_RESPONSE_BYTES:
                    return None
                chunks.append(chunk)
            return b"".join(chunks)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            raise UpstreamError("User not found on Duolingo")
        raise UpstreamError("Failed to fetch: HTTP %d %s" % (e.code, e.reason))
    except (urllib.error.URLError, socket.timeout, TimeoutError, OSError):
        return None


class UpstreamError(Exception):
    """Upstream refused the request (definitive HTTP error, no cache fallback)."""


def _clean_str(value, limit):
    if not isinstance(value, str):
        return ""
    value = value.strip()
    return value if 0 < len(value) <= limit else ""


def _truncated_str(value, limit):
    """Trim to limit; over-long values are cut, not discarded."""
    if not isinstance(value, str):
        return ""
    return value.strip()[:limit]


def normalize(body):
    """Validate schema and project the upstream user into the plugin shape.

    Returns a dict or None when the response violates the schema.
    """
    try:
        parsed = json.loads(body.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return None
    if not isinstance(parsed, dict):
        return None
    users = parsed.get("users")
    if not isinstance(users, list) or len(users) != MAX_MATCHES:
        return None
    user = users[0]
    if not isinstance(user, dict):
        return None
    username = _clean_str(user.get("username"), 25)
    if not username or not USERNAME_RE.match(username):
        return None
    # QML consumer contract fields (Panel hero + course rows).
    # Privacy: the upstream display name (often the legal name) is never
    # projected or persisted; the public username doubles as the title.
    fullname = username
    avatar = _clean_str(user.get("picture"), MAX_STR)
    if avatar.startswith("//"):
        avatar = "https:" + avatar
    if avatar and not avatar.startswith("https://"):
        avatar = ""  # only https accepted
    streak = user.get("streak", 0)
    if not isinstance(streak, int) or isinstance(streak, bool) or not 0 <= streak <= 100000:
        return None
    total_xp = user.get("totalXp", 0)
    if not isinstance(total_xp, int) or isinstance(total_xp, bool) or not 0 <= total_xp <= 100_000_000:
        return None
    extended = user.get("streak_extended_today") is True
    # Public streak metadata: start date of the current streak (ISO date only).
    streak_start = ""
    streak_data = user.get("streakData")
    if isinstance(streak_data, dict):
        current = streak_data.get("currentStreak")
        if isinstance(current, dict):
            raw_start = current.get("startDate")
            if isinstance(raw_start, str) and re.match(r"^\d{4}-\d{2}-\d{2}$", raw_start):
                streak_start = raw_start
    raw_courses = user.get("courses", [])
    if not isinstance(raw_courses, list) or len(raw_courses) > MAX_COURSES:
        return None
    courses = []
    for course in raw_courses:
        if not isinstance(course, dict):
            return None
        title = _clean_str(course.get("title"), MAX_STR_LONG)
        lang = _clean_str(course.get("learningLanguage"), 16)
        if not lang or not re.match(r"^[a-z]{2,8}$", lang):
            return None
        xp = course.get("xp", 0)
        crowns = course.get("crowns", 0)
        if not isinstance(xp, int) or isinstance(xp, bool) or not 0 <= xp <= 100_000_000:
            return None
        if not isinstance(crowns, int) or isinstance(crowns, bool) or not 0 <= crowns <= 100000:
            return None
        courses.append({"title": title or lang, "learningLanguage": lang,
                        "xp": xp, "crowns": crowns})
    courses.sort(key=lambda c: c["xp"], reverse=True)
    max_course_xp = max((c["xp"] for c in courses), default=1) or 1
    for c in courses:
        c["flag"] = FLAG_MAP.get(c["learningLanguage"], "🌐")
        c["fraction"] = c["xp"] / max_course_xp
    return {
        "valid": True,
        "username": username,
        "fullname": fullname,
        "avatar": avatar,
        "streak": streak,
        "streakExtendedToday": extended,
        "streakStart": streak_start,
        "totalXp": total_xp,
        "courses": courses,
        "topCourse": courses[0] if courses else None,
        "coursesCount": len(courses),
        "lastUpdated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }


def _cache_write(payload):
    try:
        dirfd = os.open(CACHE_DIR, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        try:
            os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)
            dirfd = os.open(CACHE_DIR, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        except OSError:
            return
    try:
        atomic_write_dirfd(dirfd, payload, max_bytes=MAX_RESPONSE_BYTES,
                           name=CACHE_NAME)
    except (DuoIOError, OSError):
        pass
    finally:
        os.close(dirfd)


def _cache_read():
    try:
        dirfd = os.open(CACHE_DIR, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        return None
    try:
        fd = os.open(CACHE_NAME, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC,
                     dir_fd=dirfd)
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if st.st_size > MAX_RESPONSE_BYTES:
            return None
        raw = read_bounded(fd, MAX_RESPONSE_BYTES)
    except (DuoIOError, OSError):
        return None
    finally:
        os.close(fd)
        os.close(dirfd)
    try:
        data = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    return data


def main():
    username = ""
    no_detect = False
    for arg in sys.argv[1:]:
        if arg == "--no-detect":
            no_detect = True
        elif not arg.startswith("-") and not username:
            username = arg.strip()
    if not username and not no_detect:
        # Optional local detection (opt-in by caller configuration).
        detect = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "detect-user.py")
        try:
            import subprocess
            res = subprocess.run([sys.executable, detect],
                                 capture_output=True, text=True, timeout=3)
            if res.returncode == 0 and res.stdout.strip():
                username = res.stdout.strip()
        except Exception:
            username = ""
    if username and not USERNAME_RE.match(username):
        username = ""
    out, code = fetch(username)
    sys.stdout.write(out + "\n")
    sys.exit(code)


if __name__ == "__main__":
    main()
