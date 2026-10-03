#!/usr/bin/env python3
"""Follow the upstream package version without reusing a fork release tag."""
import re
import sys


def next_version(upstream, tags):
    if not re.fullmatch(r"\d+\.\d+\.\d+", upstream):
        raise ValueError("expected an upstream semantic version")
    versions = [tuple(map(int, tag.split('.'))) for tag in tags
                if re.fullmatch(r"\d+\.\d+\.\d+", tag)]
    latest = max(versions, default=(0, 0, 0))
    candidate = max(tuple(map(int, upstream.split('.'))), (*latest[:2], latest[2] + 1))
    return '.'.join(map(str, candidate))


if __name__ == '__main__':
    print(next_version(sys.argv[1], [line.strip() for line in sys.stdin]))
