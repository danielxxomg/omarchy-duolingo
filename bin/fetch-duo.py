#!/usr/bin/env python3
import urllib.request
import urllib.parse
import urllib.error
import sys
import os
import json
import subprocess
import tempfile
import socket

CACHE_DIR = os.path.expanduser("~/.local/state/duolingo")
CACHE_FILE = os.path.join(CACHE_DIR, "duolingo-cache.json")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def get_username(arg):
    if arg and arg.strip():
        return arg.strip()
    detect_script = os.path.join(SCRIPT_DIR, "detect-user.py")
    if os.path.exists(detect_script):
        try:
            res = subprocess.run([sys.executable, detect_script], capture_output=True, text=True, timeout=3)
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass
    return ""


def atomic_write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    dir_name = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=dir_name)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass
        raise


def print_cache_if_exists():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r") as f:
                print(f.read())
                return True
        except Exception:
            pass
    return False


def main():
    raw_user = sys.argv[1] if len(sys.argv) > 1 else ""
    username = get_username(raw_user)

    if not username:
        if print_cache_if_exists():
            sys.exit(0)
        print(json.dumps({"error": "No username provided or detected"}))
        sys.exit(1)

    url = f"https://www.duolingo.com/2017-06-30/users?username={urllib.parse.quote(username)}"
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    })

    try:
        with urllib.request.urlopen(req, timeout=7) as resp:
            content = resp.read().decode("utf-8")
            atomic_write(CACHE_FILE, content)
            print(content)
            sys.exit(0)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(json.dumps({"error": "User not found on Duolingo"}))
            sys.exit(1)
        # Other HTTP errors: report without stale fallback
        print(json.dumps({"error": f"Failed to fetch: HTTP {e.code} {e.reason}"}))
        sys.exit(1)
    except (urllib.error.URLError, socket.timeout, TimeoutError) as e:
        if print_cache_if_exists():
            sys.exit(0)
        print(json.dumps({"error": f"Failed to fetch: {str(e)}"}))
        sys.exit(1)
    except Exception as e:
        # Generic errors treated as transport fallback if possible, else error
        if isinstance(e, OSError):
            if print_cache_if_exists():
                sys.exit(0)
        print(json.dumps({"error": f"Failed to fetch: {str(e)}"}))
        sys.exit(1)


if __name__ == "__main__":
    main()
