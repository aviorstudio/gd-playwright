#!/usr/bin/env python3
"""Build the GDAM asset from the repository's closed addon manifest."""

from __future__ import annotations

import argparse
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import tempfile
import zipfile


def read_manifest(path: Path) -> list[str]:
    entries = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    if entries != sorted(set(entries)):
        raise ValueError("package manifest must be sorted and contain unique entries")
    for entry in entries:
        candidate = PurePosixPath(entry)
        if candidate.is_absolute() or ".." in candidate.parts or entry.endswith("/"):
            raise ValueError(f"unsafe package manifest entry: {entry}")
    return entries


def source_files(source: Path) -> list[str]:
    result: list[str] = []
    for path in source.rglob("*"):
        relative = path.relative_to(source).as_posix()
        if path.is_symlink():
            raise ValueError(f"addon source contains a symlink: {relative}")
        if path.is_file():
            result.append(relative)
    return sorted(result)


def package(source: Path, manifest: Path, output: Path) -> None:
    entries = read_manifest(manifest)
    actual = source_files(source)
    if actual != entries:
        missing = sorted(set(entries) - set(actual))
        undeclared = sorted(set(actual) - set(entries))
        raise ValueError(f"closed manifest mismatch; missing={missing}, undeclared={undeclared}")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="gd-playwright-package-") as temporary:
        root = Path(temporary)
        for entry in entries:
            destination = root / entry
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / entry, destination)
            os.chmod(destination, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)

        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for entry in entries:
                info = zipfile.ZipInfo(entry, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                archive.writestr(info, (root / entry).read_bytes(), compresslevel=9)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("gd/addon"))
    parser.add_argument("--manifest", type=Path, default=Path("gd/package-manifest.txt"))
    parser.add_argument("--output", type=Path, default=Path("dist/@aviorstudio_gd-playwright.zip"))
    args = parser.parse_args()
    package(args.source, args.manifest, args.output)


if __name__ == "__main__":
    main()
