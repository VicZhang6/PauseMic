#!/usr/bin/env python3
"""Block private signing material without printing its contents. No third-party dependencies."""
import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath

MAX_BYTES = 64 * 1024 * 1024
PRIVATE_KEY = re.compile(rb"-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----")
PRIVATE_SUFFIXES = {".p12", ".pfx", ".p8", ".key", ".pem"}
PRIVATE_NAMES = {"id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"}


def inspect(name, data):
    basename = PurePosixPath(name.replace("\\", "/")).name.lower()
    if PurePosixPath(basename).suffix in PRIVATE_SUFFIXES or basename in PRIVATE_NAMES:
        raise ValueError(f"Blocked private-key/signing file: {name}")
    if basename == ".env" or (basename.startswith(".env.") and basename not in {".env.example", ".env.sample"}):
        raise ValueError(f"Blocked local credential file: {name}")
    if len(data) > MAX_BYTES:
        raise ValueError(f"File exceeds scanner limit; refusing to upload: {name}")
    if PRIVATE_KEY.search(data):
        raise ValueError(f"Blocked private-key content: {name}")


def git(*args):
    return subprocess.check_output(["git", *args])


def scan_git(history=False):
    if history:
        revisions = git("rev-list", "--all").decode().splitlines()
        entries = []
        for revision in revisions:
            for entry in git("ls-tree", "-r", "-z", revision).split(b"\0"):
                if not entry:
                    continue
                metadata, name = entry.split(b"\t", 1)
                mode, kind, oid = metadata.split()
                if kind == b"blob":
                    entries.append((name.decode("utf-8", "surrogateescape"), oid.decode()))
    else:
        entries = []
        for entry in git("ls-files", "--stage", "-z").split(b"\0"):
            if not entry:
                continue
            metadata, name = entry.split(b"\t", 1)
            mode, oid, stage = metadata.split()
            if stage != b"0":
                raise ValueError("Resolve the merge conflict before checking staged files")
            if mode != b"160000":  # A gitlink is not a blob.
                entries.append((name.decode("utf-8", "surrogateescape"), oid.decode()))
    seen = set()
    for name, oid in entries:
        if (name, oid) in seen:
            continue
        seen.add((name, oid))
        size = int(git("cat-file", "-s", oid))
        if size > MAX_BYTES:
            raise ValueError(f"File exceeds scanner limit; refusing to upload: {name}")
        inspect(name, git("cat-file", "blob", oid))


def scan_artifact(path):
    if path.is_dir():
        for entry in path.rglob("*"):
            if entry.is_symlink():
                raise ValueError(f"Unexpected symlink in release bundle: {entry}")
            if entry.is_file():
                scan_artifact(entry)
        return
    if path.stat().st_size > MAX_BYTES:
        raise ValueError(f"Artifact exceeds scanner limit: {path}")
    inspect(str(path), path.read_bytes())
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for entry in archive.infolist():
                if entry.is_dir():
                    continue
                if entry.file_size > MAX_BYTES:
                    raise ValueError(f"ZIP entry exceeds scanner limit: {entry.filename}")
                data = archive.read(entry)
                inspect(entry.filename, data)
                # Refuse nested archives instead of allowing an unscanned container.
                if data.startswith((b"PK\x03\x04", b"PK\x05\x06", b"PK\x07\x08")):
                    raise ValueError(f"Nested ZIP is not allowed in release artifacts: {entry.filename}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--staged", action="store_true")
    modes.add_argument("--history", action="store_true")
    modes.add_argument("--artifacts", nargs="+", type=Path)
    args = parser.parse_args()
    try:
        if args.artifacts:
            for path in args.artifacts:
                scan_artifact(path)
        else:
            scan_git(history=args.history)
    except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Upload safety check failed: {error}", file=sys.stderr)
        return 1
    print("Private-key upload check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
