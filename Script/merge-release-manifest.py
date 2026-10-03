#!/usr/bin/env python3
"""Merge manifest structure while deferring generated binary metadata to release CI."""

import pathlib
import re
import subprocess
import sys


def normalize(text):
    text, urls = re.subn(
        r'url: "(?:__DOWNLOAD_URL__|https://github.com/[^"\n]+/releases/download/[^"\n]+/GhosttyKit\.xcframework\.zip)"',
        'url: "__DOWNLOAD_URL__"', text,
    )
    text, checksums = re.subn(r'checksum: "(?:__CHECKSUM__|[0-9a-f]{64})"', 'checksum: "__CHECKSUM__"', text)
    if (urls, checksums) != (1, 1):
        raise ValueError("expected exactly one generated XCFramework URL and checksum")
    return text


def main():
    ancestor, current, other = map(pathlib.Path, sys.argv[1:])
    for path in (ancestor, current, other):
        path.write_text(normalize(path.read_text()))
    return subprocess.run(["git", "merge-file", str(current), str(ancestor), str(other)]).returncode


if __name__ == "__main__":
    sys.exit(main())
