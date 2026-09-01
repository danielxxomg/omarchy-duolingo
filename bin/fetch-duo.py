#!/usr/bin/env python3
import urllib.request, urllib.parse, urllib.error
import sys, os, json, subprocess

CACHE_DIR = os.path.expanduser("~/.local/state/omarchy")
CACHE_FILE = os.path.join(CACHE_DIR, "duolingo-cache.json")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def get_username(arg):
    if arg and arg.strip():
        return arg.strip()
    # Try running detect-user.py
    detect_script = os.path.join(SCRIPT_DIR, "detect-user.py")
    if os.path.exists(detect_script):
        try:
            res = subprocess.run([sys.executable, detect_script], capture_output=True, text=True, timeout=3)
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass
    return ""

def main():
    raw_user = sys.argv[1] if len(sys.argv) > 1 else ""
    username = get_username(raw_user)

    if not username:
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    print(f.read())
                    sys.exit(0)
            except Exception:
                pass
        print(json.dumps({"error": "No username provided or detected"}))
        sys.exit(1)

    url = f"https://www.duolingo.com/2017-06-30/users?username={urllib.parse.quote(username)}"
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    })

    try:
        with urllib.request.urlopen(req, timeout=7) as resp:
            content = resp.read().decode("utf-8")
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(CACHE_FILE, "w") as f:
                f.write(content)
            print(content)
            sys.exit(0)
    except Exception as e:
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    print(f.read())
                    sys.exit(0)
            except Exception:
                pass
        print(json.dumps({"error": f"Failed to fetch: {str(e)}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
