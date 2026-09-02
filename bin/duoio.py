#!/usr/bin/env python3
"""Hardened low-level file I/O helpers for the Duolingo plugin helpers.

Security contract (marketplace review #4297, findings on cache/history
persistence):
- Reads are descriptor-bound, no-follow, regular-file-only, and size-capped.
- Writes are exclusive 0600, atomic via rename under a pinned directory fd,
  with revision revalidation and directory fsync.
- No operation traverses mutable parents by absolute pathname after the
  directory fd is pinned.
"""
import errno
import os
import re
import stat

MAX_READ_BYTES = 4 * 1024 * 1024  # 4 MiB ceiling for any single bounded read

# O_NONBLOCK: opening a FIFO read-only would otherwise block until a writer
# appears. For regular files it is a no-op. Type is verified via fstat right
# after open, so no attacker-controlled file can stall or wedge the helper.
_OPEN_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK
_WRITE_FLAGS = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC

_REV_RE = re.compile(r'"rev"\s*:\s*(\d+)')


class DuoIOError(OSError):
    """Refuse-to-operate condition: wrong type, over cap, missing, invalid."""


class RevConflict(DuoIOError):
    """On-disk revision is not older than the revision being written."""


def open_regular_nofollow(path):
    """Open a regular file without following symlinks; verify via fstat.

    Returns a file descriptor. Raises DuoIOError for symlinks, non-regular
    files, and missing/unreadable paths. The fstat check happens on the
    descriptor, so the file cannot be swapped between open and verify.
    """
    try:
        fd = os.open(path, _OPEN_FLAGS)
    except FileNotFoundError:
        raise DuoIOError(errno.ENOENT, os.strerror(errno.ENOENT), path)
    except OSError as e:
        raise DuoIOError(e.errno, e.strerror, path)
    try:
        st = os.fstat(fd)
    except OSError as e:
        os.close(fd)
        raise DuoIOError(e.errno, e.strerror, path)
    if not stat.S_ISREG(st.st_mode):
        os.close(fd)
        raise DuoIOError(errno.EINVAL, "not a regular file", path)
    return fd


def read_bounded(fd, limit):
    """Read up to `limit` bytes through the descriptor.

    Raises DuoIOError if the file is larger than `limit` — a state file that
    does not fit is corruption, never silently truncated.
    """
    if not isinstance(limit, int) or isinstance(limit, bool):
        raise DuoIOError(errno.EINVAL, "invalid read limit", str(limit))
    if limit <= 0 or limit > MAX_READ_BYTES:
        raise DuoIOError(errno.EINVAL, "invalid read limit", str(limit))
    st = os.fstat(fd)
    if st.st_size > limit:
        raise DuoIOError(errno.EFBIG, "file larger than limit", str(st.st_size))
    chunks = []
    got = 0
    while got < limit:
        chunk = os.read(fd, limit - got)
        if not chunk:
            break
        chunks.append(chunk)
        got += len(chunk)
    return b"".join(chunks)


def atomic_write_dirfd(dirfd, payload, max_bytes, expect_rev_less_than=None,
                       name="duolingo-state.json"):
    """Exclusive 0600 atomic write anchored to a pinned directory fd.

    - payload over max_bytes is refused before any I/O.
    - expect_rev_less_than: refuse with RevConflict when an existing state
      file's "rev" is >= the value being written. Revalidated again right
      before the rename to close the check-vs-use window.
    - fsyncs the temp file and the directory so the rename is durable.
    """
    payload_bytes = payload.encode("utf-8")
    if len(payload_bytes) > max_bytes:
        raise DuoIOError(errno.EFBIG, "payload over cap", str(len(payload_bytes)))
    if expect_rev_less_than is not None:
        _check_rev(dirfd, name, expect_rev_less_than)
    tmp = "%s.tmp.%d.%s" % (name, os.getpid(), os.urandom(6).hex())
    fd = os.open(tmp, _WRITE_FLAGS, 0o600, dir_fd=dirfd)
    try:
        view = memoryview(payload_bytes)
        while view:
            wrote = os.write(fd, view)
            view = view[wrote:]
        os.fchmod(fd, 0o600)
        os.fsync(fd)
        # Revalidate before rename: another writer may have landed meanwhile.
        if expect_rev_less_than is not None:
            _check_rev(dirfd, name, expect_rev_less_than)
        os.rename(tmp, name, src_dir_fd=dirfd, dst_dir_fd=dirfd)
    except BaseException:
        try:
            os.unlink(tmp, dir_fd=dirfd)
        except OSError:
            pass
        raise
    finally:
        os.close(fd)
    os.fsync(dirfd)
    return True


def _check_rev(dirfd, name, expect_rev_less_than):
    """Read the on-disk rev through dirfd; refuse when it is >= ours."""
    try:
        fd = os.open(name, _OPEN_FLAGS, dir_fd=dirfd)
    except FileNotFoundError:
        return
    except OSError as e:
        raise DuoIOError(e.errno, e.strerror, name)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise DuoIOError(errno.EINVAL, "not a regular file", name)
        head = os.read(fd, 64)
    finally:
        os.close(fd)
    match = _REV_RE.search(head.decode("ascii", errors="ignore"))
    if match and int(match.group(1)) >= expect_rev_less_than:
        raise RevConflict(errno.EEXIST, "equal or newer revision on disk", name)