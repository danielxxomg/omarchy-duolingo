#!/usr/bin/env python3
import glob
import os
import re
import base64
import gzip
import json
import sys

MAX_FILE_SIZE = 16 * 1024 * 1024
MAX_TOTAL_BYTES = 64 * 1024 * 1024


def detect_duolingo_user():
    db_paths = [
        os.path.expanduser("~/.config/DL: language lessons/Local Storage/leveldb/*"),
        os.path.expanduser("~/.config/BraveSoftware/Brave-Browser/Default/Local Storage/leveldb/*"),
        os.path.expanduser("~/.config/google-chrome/Default/Local Storage/leveldb/*"),
        os.path.expanduser("~/.config/chromium/Default/Local Storage/leveldb/*"),
    ]
    total_bytes = 0
    for pattern in db_paths:
        for f in glob.glob(pattern):
            if os.path.islink(f):
                continue
            if not os.path.isfile(f):
                continue
            try:
                size = os.path.getsize(f)
            except Exception:
                continue
            if size > MAX_FILE_SIZE:
                continue
            if total_bytes + size > MAX_TOTAL_BYTES:
                return ""
            try:
                with open(f, "rb") as fp:
                    content = fp.read().decode("latin1", errors="ignore")
                    total_bytes += len(content.encode("latin1", errors="ignore"))
                    if total_bytes > MAX_TOTAL_BYTES:
                        return ""
                    matches = re.findall(r'"(H4sIAAAAA[^"]+)"', content)
                    for m in matches:
                        try:
                            m_padded = m + "=" * (-len(m) % 4)
                            decompressed = gzip.decompress(base64.b64decode(m_padded)).decode("utf-8")
                            data = json.loads(decompressed)
                            redux = data.get("state", {}).get("redux", {})
                            if isinstance(redux, str):
                                redux = json.loads(redux)
                            if "user" in redux and redux["user"].get("username"):
                                return redux["user"]["username"]
                        except Exception:
                            pass
            except Exception:
                pass
            if total_bytes >= MAX_TOTAL_BYTES:
                return ""
    return ""


if __name__ == "__main__":
    user = detect_duolingo_user()
    if user:
        print(user)
        sys.exit(0)
    sys.exit(1)
