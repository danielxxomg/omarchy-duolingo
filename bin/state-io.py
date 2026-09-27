#!/usr/bin/env python3
"""History state I/O for the QML service.

Contract (marketplace review #4297, findings #4 and #5):
- The private history JSON travels over stdin, never in process argv
  (argv is world-readable via /proc/<pid>/cmdline).
- Reads: descriptor-bound, no-follow, regular-file-only, size-capped.
- Writes: exclusive 0600 atomic rename anchored to a pinned directory fd,
  with revision revalidation and fsync (duoio.atomic_write_dirfd).
- Stdin payload is size-capped before parsing; output is the file content
  (capped) or an empty stream on any refusal.

Usage:
  state-io.py read
  state-io.py write  < rev-file  (payload on stdin, rev passed via fd 0? no —)
  state-io.py write REVFILE < payload
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from duoio import (  # noqa: E402
    DuoIOError,
    RevConflict,
    atomic_write_dirfd,
    open_regular_nofollow,
    read_bounded,
)

STATE_DIR = os.path.expanduser("~/.local/state/duolingo")
STATE_NAME = "history.json"
MAX_STATE_BYTES = 256 * 1024


def do_read(state_dir, state_name):
    try:
        dirfd = os.open(state_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        sys.exit(0)  # no state yet: empty output, success
    try:
        fd = os.open(state_name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC,
                     dir_fd=dirfd)
    except FileNotFoundError:
        sys.exit(0)
    except OSError:
        sys.exit(1)
    try:
        try:
            raw = read_bounded(fd, MAX_STATE_BYTES)
        except DuoIOError:
            sys.exit(1)
    finally:
        os.close(fd)
        os.close(dirfd)
    sys.stdout.buffer.write(raw)
    sys.exit(0)


def do_write(state_dir, state_name, rev, payload):
    if len(payload) > MAX_STATE_BYTES:
        sys.exit(2)
    try:
        dirfd = os.open(state_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        try:
            os.makedirs(state_dir, mode=0o700, exist_ok=True)
            dirfd = os.open(state_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        except OSError:
            sys.exit(1)
    try:
        atomic_write_dirfd(dirfd, payload.decode("utf-8"), max_bytes=MAX_STATE_BYTES,
                           expect_rev_less_than=rev, name=state_name)
    except RevConflict:
        sys.exit(3)
    except (DuoIOError, OSError):
        sys.exit(1)
    finally:
        os.close(dirfd)
    sys.exit(0)


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(64)
    verb = args[0]
    state_dir = os.environ.get("DUO_STATE_DIR", STATE_DIR)
    if verb == "read":
        do_read(state_dir, STATE_NAME)
    elif verb == "write":
        if len(args) != 2:
            sys.exit(64)
        try:
            rev = int(args[1])
        except ValueError:
            sys.exit(64)
        if rev < 0:
            sys.exit(64)
        payload = sys.stdin.buffer.read(MAX_STATE_BYTES + 1)
        do_write(state_dir, STATE_NAME, rev, payload)
    else:
        sys.exit(64)


if __name__ == "__main__":
    main()