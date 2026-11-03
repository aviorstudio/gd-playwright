#!/usr/bin/env python3
"""Reachable positive and negative controls for the closed package gate."""

from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

from package_gd import package
from verify_gd_package import verify


class PackageGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="gd-package-gate-")
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        (self.source / "plugin.cfg").write_text("[plugin]\n")
        (self.source / "plugin.gd").write_text("@tool\nextends EditorPlugin\n")
        self.manifest = self.root / "manifest.txt"
        self.manifest.write_text("plugin.cfg\nplugin.gd\n")
        self.archive = self.root / "addon.zip"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_known_good_package_passes_and_assertion_is_reached(self) -> None:
        package(self.source, self.manifest, self.archive)
        zip_digest, tree_digest = verify(self.archive, self.manifest)
        self.assertEqual(len(zip_digest), 64)
        self.assertEqual(len(tree_digest), 64)
        print("ASSERTION_REACHED package_known_good")

    def test_source_symlink_is_rejected(self) -> None:
        (self.source / "link.gd").symlink_to("plugin.gd")
        with self.assertRaisesRegex(ValueError, "symlink"):
            package(self.source, self.manifest, self.archive)

    def test_undeclared_source_file_is_rejected(self) -> None:
        (self.source / "test_only.gd").write_text("development artifact")
        with self.assertRaisesRegex(ValueError, "undeclared"):
            package(self.source, self.manifest, self.archive)

    def test_missing_declared_file_is_rejected(self) -> None:
        (self.source / "plugin.gd").unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            package(self.source, self.manifest, self.archive)

    def _write_zip(self, entries: list[tuple[zipfile.ZipInfo | str, bytes]]) -> None:
        with zipfile.ZipFile(self.archive, "w") as archive:
            for name, data in entries:
                archive.writestr(name, data)

    def test_traversal_path_is_rejected(self) -> None:
        self._write_zip([("../plugin.cfg", b"x"), ("plugin.gd", b"x")])
        with self.assertRaisesRegex(ValueError, "manifest mismatch|unsafe"):
            verify(self.archive, self.manifest)

    def test_zip_symlink_is_rejected(self) -> None:
        link = zipfile.ZipInfo("plugin.cfg")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self._write_zip([(link, b"plugin.gd"), ("plugin.gd", b"x")])
        with self.assertRaisesRegex(ValueError, "not a regular file"):
            verify(self.archive, self.manifest)

    def test_unexpected_development_artifact_is_rejected(self) -> None:
        self._write_zip([
            ("plugin.cfg", b"x"),
            ("plugin.gd", b"x"),
            ("tests/secret_fixture.gd", b"x"),
        ])
        with self.assertRaisesRegex(ValueError, "undeclared"):
            verify(self.archive, self.manifest)


if __name__ == "__main__":
    unittest.main(verbosity=2)
