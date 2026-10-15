import os
from pathlib import Path
import platform
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

import package_macos as packaging


def make_app(root, native=False):
    app = root / packaging.APP_NAME
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    info = {
        "CFBundleIdentifier": packaging.BUNDLE_ID,
        "CFBundleExecutable": "Ndisafe-desk",
        "CFBundleName": "NDISafe Desk",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.0.1",
        "CFBundleVersion": "1",
        "CFBundleIconFile": "AppIcon.icns",
        "LSMinimumSystemVersion": "10.14",
        "NSCameraUsageDescription": "Video support",
        "NSMicrophoneUsageDescription": "Audio support",
    }
    with (app / "Contents/Info.plist").open("wb") as dest:
        plistlib.dump(info, dest)
    if native:
        source = root / "main.c"
        source.write_text('#include <stdio.h>\nint main(void) { puts("0.0.1"); return 0; }\n',
                          encoding="ascii")
        packaging.run("clang", str(source), "-o", macos / "Ndisafe-desk")
    else:
        (macos / "Ndisafe-desk").write_bytes(b"\xcf\xfa\xed\xfe" + b"test executable")
        (macos / "Ndisafe-desk").chmod(0o755)
    shutil.copy2(macos / "Ndisafe-desk", macos / "service")
    shutil.copy2(packaging.ROOT / "flutter/macos/Runner/AppIcon.icns",
                 resources / "AppIcon.icns")
    return app


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ndisafe-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = make_app(self.root)
        self.runner = patch.object(packaging, "run", return_value=b"").start()
        self.addCleanup(patch.stopall)

    def test_version_and_helper_are_checked_before_packaging(self):
        packaging.validate_bundle(self.app, "0.0.1")
        with self.assertRaisesRegex(packaging.PackageError, "version"):
            packaging.validate_bundle(self.app, "1.4.13")
        (self.app / "Contents/MacOS/service").unlink()
        with self.assertRaisesRegex(packaging.PackageError, "service"):
            packaging.validate_bundle(self.app)

    def test_old_icon_is_rejected(self):
        (self.app / "Contents/Resources/AppIcon.icns").write_bytes(b"icnsold-logo")
        with self.assertRaisesRegex(packaging.PackageError, "outdated"):
            packaging.validate_bundle(self.app)

    def test_architecture_check_uses_lipo_input_before_variadic_architectures(self):
        packaging.validate_bundle(self.app, "0.0.1", "aarch64")
        for name in ("Ndisafe-desk", "service"):
            self.runner.assert_any_call("lipo", self.app / "Contents/MacOS" / name,
                                        "-verify_arch", "arm64")

    def test_missing_camera_permission_is_rejected(self):
        path = self.app / "Contents/Info.plist"
        with path.open("rb") as source:
            info = plistlib.load(source)
        del info["NSCameraUsageDescription"]
        with path.open("wb") as dest:
            plistlib.dump(info, dest)
        with self.assertRaisesRegex(packaging.PackageError, "NSCamera"):
            packaging.validate_bundle(self.app)

    def test_library_identity_is_not_an_external_dependency(self):
        self.runner.return_value = b"""App:
Load command 1
          cmd LC_ID_DYLIB
      cmdsize 112
         name /Users/runner/build/App.framework/Versions/A/App (offset 24)
Load command 2
          cmd LC_LOAD_DYLIB
      cmdsize 56
         name /usr/lib/libSystem.B.dylib (offset 24)
Load command 3
          cmd LC_LOAD_WEAK_DYLIB
      cmdsize 80
         name @rpath/Example.framework/Versions/A/Example (offset 24)
"""
        self.assertEqual(list(packaging.linked_libraries(self.app)), [
            "/usr/lib/libSystem.B.dylib", "@rpath/Example.framework/Versions/A/Example",
        ])
        with patch.object(packaging.sys, "platform", "darwin"):
            packaging.validate_bundle(self.app)

    def test_external_runtime_dependency_is_rejected(self):
        self.runner.return_value = b"""App:
Load command 1
          cmd LC_LOAD_DYLIB
         name /opt/homebrew/lib/libexample.dylib (offset 24)
"""
        with patch.object(packaging.sys, "platform", "darwin"):
            with self.assertRaisesRegex(packaging.PackageError, "Nonportable library dependency"):
                packaging.validate_bundle(self.app)

    def test_nested_code_is_signed_before_outer_bundle(self):
        framework = self.app / "Contents/Frameworks/Example.framework"
        framework.mkdir(parents=True)
        (framework / "Example").write_bytes(b"\xcf\xfa\xed\xfe" + b"framework")
        packaging.sign_bundle(self.app)
        signing = [call.args for call in self.runner.call_args_list
                   if call.args[:2] == ("codesign", "--force")]
        paths = [call[-1] for call in signing]
        self.assertLess(paths.index(framework / "Example"), paths.index(framework))
        self.assertEqual(paths[-1], self.app)
        self.assertNotIn(self.app / "Contents/MacOS/Ndisafe-desk", paths)
        self.assertLess(paths.index(self.app / "Contents/MacOS/service"), paths.index(self.app))
        self.assertTrue(all("--deep" not in call for call in signing))
        self.assertIn(unittest.mock.call("codesign", "--verify", "--deep", "--strict",
                                        "--verbose=2", self.app), self.runner.call_args_list)

    def test_symlink_cannot_escape_application(self):
        link = self.app / "Contents/Resources/outside"
        try:
            link.symlink_to(self.root, target_is_directory=True)
        except OSError:
            self.skipTest("Creating symlinks is unavailable on this host")
        with self.assertRaisesRegex(packaging.PackageError, "leaves application"):
            packaging.bundle_code(self.app)

    def test_partial_signing_configuration_never_silently_downgrades(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(packaging.signing_config())
            os.environ["MACOS_CODESIGN_IDENTITY"] = "Developer ID Application: Test"
            with self.assertRaisesRegex(packaging.PackageError, "Incomplete"):
                packaging.signing_config()

    def test_notarization_rejection_is_an_error(self):
        self.runner.return_value = b'{"status":"Invalid","id":"test-submission"}'
        with patch.dict(os.environ, {
            "MACOS_APPLE_ID": "test@example.invalid", "MACOS_TEAM_ID": "test",
            "MACOS_APP_PASSWORD": "test-password",
        }):
            with self.assertRaisesRegex(packaging.PackageError, "test-submission"):
                packaging.notarize(self.root / "app.zip")

    def test_mounted_image_without_app_is_rejected_and_unmounted(self):
        with patch.object(packaging.tempfile, "TemporaryDirectory") as directory:
            directory.return_value.__enter__.return_value = str(self.root)
            with self.assertRaisesRegex(packaging.PackageError, "DMG must contain"):
                packaging.verify_dmg(self.root / "bad.dmg", "0.0.1", "x86_64")
            self.runner.assert_any_call("hdiutil", "detach", self.root / "volume")


@unittest.skipUnless(sys.platform == "darwin", "Requires Apple's macOS packaging tools")
class MacIntegrationTests(unittest.TestCase):
    def test_signed_bundle_dmg_mount_and_pkg_payload(self):
        with tempfile.TemporaryDirectory(prefix="ndisafe-integration-") as temporary:
            root = Path(temporary)
            app = make_app(root, native=True)
            frameworks = app / "Contents/Frameworks"
            frameworks.mkdir()
            packaging.run("clang", "-dynamiclib", root / "main.c", "-install_name",
                          root / "build-only/libfixture.dylib",
                          "-o", frameworks / "libfixture.dylib")
            arch = "aarch64" if platform.machine() == "arm64" else "x86_64"
            with patch.dict(os.environ, {name: "" for name in packaging.SIGNING_ENV}):
                try:
                    packaging.package(app, "0.0.1", arch, root / "out", finder=False)
                except Exception as error:
                    if os.environ.get("GITHUB_ACTIONS"):
                        message = str(error).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
                        print(f"::error title=macOS installer integration::{message}", flush=True)
                    raise
            self.assertTrue((root / "out" / f"ndisafe-desk-0.0.1-{arch}.dmg.sha256").exists())
            self.assertTrue((root / "out" / f"NDISafe-Desk-0.0.1-{arch}.pkg.sha256").exists())
            if os.environ.get("GITHUB_ACTIONS") == "true":
                self.assert_installer_upgrades_existing_app(root, app, arch)
            packaging.sign_bundle(app)
            (app / "Contents/Resources/unsealed.txt").write_text("changed after signing")
            with self.assertRaises(packaging.PackageError):
                packaging.run("codesign", "--verify", "--deep", "--strict", app)

    def assert_installer_upgrades_existing_app(self, root, app, arch):
        installed = Path("/Applications") / packaging.APP_NAME
        if installed.exists() or installed.is_symlink():
            self.fail("Refusing to replace an existing app on the test runner")
        old_app = root / "old" / packaging.APP_NAME
        old_app.parent.mkdir()
        packaging.run("ditto", app, old_app)
        info_path = old_app / "Contents/Info.plist"
        with info_path.open("rb") as source:
            info = plistlib.load(source)
        info.update(CFBundleIdentifier="com.carriez.rustdesk",
                    CFBundleShortVersionString="0.0.0", CFBundleVersion="0")
        with info_path.open("wb") as dest:
            plistlib.dump(info, dest)
        (old_app / "Contents/Resources/obsolete.txt").write_text("old installation")
        try:
            packaging.run("sudo", "-n", "ditto", old_app, installed)
            packaging.run("sudo", "-n", "/usr/sbin/installer", "-pkg",
                          root / "out" / f"NDISafe-Desk-0.0.1-{arch}.pkg", "-target", "/")
            packaging.validate_bundle(installed, "0.0.1", arch)
            self.assertFalse((installed / "Contents/Resources/obsolete.txt").exists(),
                             "PKG upgrade retained obsolete files from the previous bundle")
            packaging.run("codesign", "--verify", "--deep", "--strict", "--verbose=4", installed)
            self.assertIn(b"0.0.1", packaging.run(installed / "Contents/MacOS/Ndisafe-desk", "--version"))
        except Exception as error:
            message = str(error).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print(f"::error title=macOS installer upgrade::{message}", flush=True)
            raise
        finally:
            packaging.run("sudo", "-n", "rm", "-rf", "--", installed)
            packaging.run("sudo", "-n", "pkgutil", "--forget", packaging.PACKAGE_ID)


if __name__ == "__main__":
    unittest.main()
