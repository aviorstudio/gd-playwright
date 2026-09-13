#!/usr/bin/env python3
"""Fail closed unless a GDAM ZIP contains exactly the declared regular files."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path, PurePosixPath
import stat
import tempfile
import zipfile

from package_gd import read_manifest


def verify(archive_path: Path, manifest_path: Path) -> tuple[str, str]:
    expected = read_manifest(manifest_path)
    with zipfile.ZipFile(archive_path) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if names != expected:
            missing = sorted(set(expected) - set(names))
            undeclared = sorted(set(names) - set(expected))
            raise ValueError(f"ZIP manifest mismatch; missing={missing}, undeclared={undeclared}")
        if len(names) != len(set(names)):
            raise ValueError("ZIP contains duplicate paths")
        for info in infos:
            path = PurePosixPath(info.filename)
            if path.is_absolute() or ".." in path.parts or info.filename.endswith("/"):
                raise ValueError(f"unsafe ZIP path: {info.filename}")
            mode = info.external_attr >> 16
            if mode and not stat.S_ISREG(mode):
                raise ValueError(f"ZIP entry is not a regular file: {info.filename}")
            archive.read(info)

        with tempfile.TemporaryDirectory(prefix="gd-playwright-install-") as temporary:
            install_root = Path(temporary)
            archive.extractall(install_root)
            installed = sorted(
                path.relative_to(install_root).as_posix()
                for path in install_root.rglob("*")
                if path.is_file()
            )
            if installed != expected:
                raise ValueError("installed tree differs from the closed manifest")
            tree = hashlib.sha256()
            for name in installed:
                data = (install_root / name).read_bytes()
                tree.update(name.encode("utf-8") + b"\0")
                tree.update(hashlib.sha256(data).digest())

    zip_digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    return zip_digest, tree.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--manifest", type=Path, default=Path("gd/package-manifest.txt"))
    args = parser.parse_args()
    zip_digest, tree_digest = verify(args.archive, args.manifest)
    print(f"GD_PACKAGE_SHA256={zip_digest}")
    print(f"GD_INSTALLED_TREE_SHA256={tree_digest}")


if __name__ == "__main__":
    main()
