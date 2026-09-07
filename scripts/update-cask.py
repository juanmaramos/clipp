#!/usr/bin/env python3
"""Update the cask from the exact ZIP produced by the release build."""
import argparse
import hashlib
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("version")
parser.add_argument("build")
parser.add_argument("archive", type=Path)
parser.add_argument("--cask", type=Path, default=Path("Casks/clipp.rb"))
args = parser.parse_args()
if not re.fullmatch(r"\d+\.\d+\.\d+", args.version) or not re.fullmatch(r"\d+", args.build):
    parser.error("Expected a semantic version and numeric build")
digest = hashlib.sha256(args.archive.read_bytes()).hexdigest()
source = args.cask.read_text()
source, versions = re.subn(r'^  version "[^"]+"$', f'  version "{args.version},{args.build}"', source, flags=re.M)
source, hashes = re.subn(r'^  sha256 "[a-f0-9]{64}"$', f'  sha256 "{digest}"', source, flags=re.M)
if versions != 1 or hashes != 1:
    parser.error("Expected exactly one cask version and SHA-256")
args.cask.write_text(source)
