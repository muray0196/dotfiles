import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import tempfile
import unittest


UPDATER = (
    Path(__file__).resolve().parents[1]
    / "modules/zsh-abbr/.local/bin/waywallen-update"
)


class WaywallenUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wwup test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.install = self.root / "versions"
        self.old = self.make_version(self.install / "1.0", "1.0")
        self.release = self.make_version(self.root / "release", "1.1")
        self.launcher = self.bin / "waywallen"
        self.backing = self.bin / "waywallen-appimage"
        self.backing.symlink_to(self.old / "AppRun")
        self.wrapper = '#!/bin/sh\nexec "$(dirname -- "$0")/waywallen-appimage" "$@"\n'
        self.write_executable(self.launcher, self.wrapper)
        payload = '#!/bin/sh\ncp -a -- "$TEST_RELEASE" squashfs-root\n'
        (self.root / "appimage").write_text(payload)
        metadata = {
            "tag_name": "v1.1",
            "assets": [{
                "name": f"waywallen-1.1-{platform.machine()}.AppImage",
                "browser_download_url": "https://example.invalid/appimage",
                "digest": "sha256:" + hashlib.sha256(payload.encode()).hexdigest(),
            }],
        }
        (self.root / "release.json").write_text(json.dumps(metadata))
        self.write_executable(
            self.bin / "curl",
            f"#!{sys.executable}\n"
            "import os, pathlib, shutil, sys\n"
            "root = pathlib.Path(os.environ['TEST_ROOT'])\n"
            "source = 'release.json' if sys.argv[-1].endswith('/latest') else 'appimage'\n"
            "shutil.copyfile(root / source, sys.argv[sys.argv.index('--output') + 1])\n",
        )
        # Never invoke real sudo or touch processes on the host.
        self.write_executable(
            self.bin / "sudo",
            f"#!{sys.executable}\n"
            "import os, pathlib, sys\n"
            "command, *args = sys.argv[1:]\n"
            "assert command in {'install', 'cp', 'mv', 'ln', 'rm'}\n"
            "root = pathlib.Path(os.environ['TEST_ROOT'])\n"
            "for arg in args[args.index('--') + 1:]:\n"
            "    assert pathlib.Path(arg).is_absolute(), arg\n"
            "    assert pathlib.Path(arg).resolve().is_relative_to(root), arg\n"
            "os.execvp(command, [command, *args])\n",
        )
        self.write_executable(self.bin / "pgrep", "#!/bin/sh\nexit 1\n")
        (self.bin / "python").symlink_to(sys.executable)
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:/usr/bin:/bin",
            TMPDIR=str(self.root),
            TEST_ROOT=str(self.root),
            TEST_RELEASE=str(self.release),
        )

    def write_executable(self, path, content):
        path.write_text(content)
        path.chmod(0o755)

    def make_version(self, directory, version):
        (directory / "usr/bin").mkdir(parents=True)
        content = f"#!/bin/sh\nprintf '%s\\n' {shlex.quote('waywallen ' + version)}\n"
        self.write_executable(directory / "AppRun", content)
        self.write_executable(directory / "usr/bin/waywallen", content)
        return directory

    def run_update(self, *args, success=True):
        result = subprocess.run(
            [str(UPDATER), *args], env=self.env, capture_output=True, text=True, timeout=30
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_direct_symlink_check(self):
        self.launcher.unlink()
        self.launcher.symlink_to(self.old / "AppRun")
        self.assertIn("1.0 installed, 1.1 latest", self.run_update("--check").stdout)
        self.assertEqual(self.launcher.resolve(), self.old / "AppRun")

    def test_wrapper_check_preserves_installation(self):
        self.assertIn("update is available", self.run_update("--check").stdout)
        self.assertEqual(self.backing.resolve(), self.old / "AppRun")
        self.assertEqual(self.launcher.read_text(), self.wrapper)
        self.assertFalse((self.install / "1.1").exists())

    def test_update_preserves_wrapper_and_rollback(self):
        self.run_update()
        self.assertEqual(self.backing.resolve(), self.install / "1.1/AppRun")
        self.assertEqual(self.launcher.read_text(), self.wrapper)
        self.assertTrue((self.old / "AppRun").exists())
        self.assertIn("already up to date", self.run_update().stdout)

    def test_update_makes_private_extraction_accessible(self):
        for path in [self.release, *self.release.rglob("*")]:
            path.chmod(0o700)
        asset = self.release / "usr/resource.txt"
        asset.write_text("wallpaper resource")
        asset.chmod(0o600)
        result = self.run_update()
        installed = self.install / "1.1"
        for path in [installed, *installed.rglob("*")]:
            expected = 0o044 if path.name == asset.name else 0o055
            self.assertEqual(path.stat().st_mode & 0o055, expected, str(path))
        self.assertEqual(self.backing.resolve(), installed / "AppRun")
        self.assertIn("Installed Waywallen 1.1", result.stdout)

    def test_unusable_installed_version_keeps_previous_launcher(self):
        sudo = self.bin / "sudo"
        sudo.write_text(sudo.read_text().replace(
            "os.execvp(command, [command, *args])",
            "import subprocess\n"
            "result = subprocess.run([command, *args], check=False)\n"
            "if result.returncode == 0 and command == 'cp':\n"
            "    (pathlib.Path(args[-1]) / 'AppRun').write_text('#!/bin/sh\\nexit 1\\n')\n"
            "sys.exit(result.returncode)",
        ))
        result = self.run_update(success=False)
        self.assertIn("launcher was left unchanged", result.stderr)
        self.assertEqual(self.backing.resolve(), self.old / "AppRun")
        self.assertEqual(self.launcher.read_text(), self.wrapper)

    def test_missing_backing_link_is_rejected(self):
        self.backing.unlink()
        result = self.run_update("--check", success=False)
        self.assertIn("must delegate to a sibling", result.stderr)
        self.assertEqual(self.launcher.read_text(), self.wrapper)

    def test_update_preserves_another_launcher_target(self):
        older = self.make_version(self.install / "0.9", "0.9")
        legacy_bin = self.root / "legacy-bin"
        legacy_bin.mkdir()
        legacy_launcher = legacy_bin / "waywallen"
        legacy_launcher.symlink_to(older / "AppRun")
        self.env["PATH"] += f":{legacy_bin}"
        self.assertIn("referenced by another launcher", self.run_update().stdout)
        self.assertTrue(legacy_launcher.exists())
        self.assertEqual(self.backing.resolve(), self.install / "1.1/AppRun")

    def test_mismatched_wrapper_is_rejected(self):
        self.write_executable(self.launcher, "#!/bin/sh\necho 'waywallen 0.9'\n")
        result = self.run_update("--check", success=False)
        self.assertIn("point to different versions", result.stderr)
        self.assertEqual(self.backing.resolve(), self.old / "AppRun")


if __name__ == "__main__":
    unittest.main()
