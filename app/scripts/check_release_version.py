#!/usr/bin/env python3
"""Fail fast on mismatched release versions before allocating build runners."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def release_tag(root=ROOT):
    project = (root / 'Nultra.xcodeproj/project.pbxproj').read_text()
    versions = set(re.findall(r'"MARKETING_VERSION" = "([^"]+)";', project))
    android = (root / 'android/app/build.gradle').read_text()
    match = re.search(r"versionName\s+'([^']+)'", android)
    if len(versions) != 1 or not match or versions != {match[1]}:
        raise ValueError('iPhone and Android versions must match')
    version = match[1]
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('Version must have the form X.X.X')
    tag = 'v' + version
    if not (root / 'docs/releases' / (tag + '.md')).is_file():
        raise ValueError('Missing release notes for ' + tag)
    return tag


if __name__ == '__main__':
    print(release_tag())
