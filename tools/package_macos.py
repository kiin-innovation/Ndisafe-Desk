"""Build and verify macOS installers after all bundle changes are complete."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP_NAME = "Ndisafe-desk.app"
BUNDLE_ID = "com.ndisafe.desk"
ENTITLEMENTS = ROOT / "flutter/macos/Runner/Release.entitlements"
SIGNING_ENV = (
    "MACOS_P12_BASE64", "MACOS_P12_PASSWORD", "MACOS_CODESIGN_IDENTITY",
    "MACOS_INSTALLER_IDENTITY", "MACOS_APPLE_ID", "MACOS_TEAM_ID",
    "MACOS_APP_PASSWORD",
)
MACHO_MAGIC = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


class PackageError(RuntimeError):
    pass


def run(*args):
    try:
        result = subprocess.run([str(arg) for arg in args], capture_output=True,
                                check=False, timeout=1200)
    except subprocess.TimeoutExpired:
        raise PackageError(f"{Path(args[0]).name} did not finish within 20 minutes") from None
    if result.returncode:
        # Arguments can contain notarization credentials; never include them in errors.
        raise PackageError(f"{Path(args[0]).name} failed ({result.returncode}): "
                           + result.stderr.decode(errors="replace"))
    return result.stdout


def signing_config():
    values = {key: os.environ.get(key, "") for key in SIGNING_ENV}
    if not any(values.values()):
        return False
    missing = [key for key, value in values.items() if not value]
    if missing:
        raise PackageError("Incomplete Apple signing configuration: " + ", ".join(missing))
    if not values["MACOS_CODESIGN_IDENTITY"].startswith("Developer ID Application:"):
        raise PackageError("MACOS_CODESIGN_IDENTITY must be a Developer ID Application identity")
    if not values["MACOS_INSTALLER_IDENTITY"].startswith("Developer ID Installer:"):
        raise PackageError("MACOS_INSTALLER_IDENTITY must be a Developer ID Installer identity")
    return True


def is_macho(path):
    with path.open("rb") as source:
        return source.read(4) in MACHO_MAGIC


def bundle_code(app):
    code = []
    for path in app.rglob("*"):
        if path.is_symlink():
            if not path.resolve().is_relative_to(app.resolve()):
                raise PackageError(f"Bundle symlink leaves application: {path}")
            if not path.exists():
                raise PackageError(f"Broken bundle symlink: {path}")
            continue
        if path.is_file() and is_macho(path):
            code.append(path)
        elif path.is_dir() and path.suffix in (".framework", ".app", ".xpc"):
            code.append(path)
    return sorted(code, key=lambda path: len(path.parts), reverse=True)


def validate_bundle(app, version=None, arch=None):
    if app.name != APP_NAME:
        raise PackageError(f"Expected {APP_NAME}, received {app.name}")
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise PackageError("Incorrect application bundle identifier")
    if info.get("CFBundleExecutable") != "Ndisafe-desk":
        raise PackageError("Application executable does not match installation paths")
    if version and info.get("CFBundleShortVersionString") != version:
        raise PackageError("Application version does not match release version")
    for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription"):
        if not info.get(key):
            raise PackageError(f"Missing macOS permission description: {key}")
    for name in ("Ndisafe-desk", "service"):
        executable = app / "Contents/MacOS" / name
        if not executable.is_file() or not is_macho(executable):
            raise PackageError(f"Missing native executable: {name}")
        if sys.platform == "darwin" and not os.access(executable, os.X_OK):
            raise PackageError(f"Executable permission missing: {name}")
    icon = app / "Contents/Resources/AppIcon.icns"
    if not icon.is_file() or icon.read_bytes()[:4] != b"icns":
        raise PackageError("Missing macOS app icon")
    if icon.read_bytes() != (ROOT / "flutter/macos/Runner/AppIcon.icns").read_bytes():
        raise PackageError("Application contains an outdated app icon")
    for path in bundle_code(app):
        if not path.is_file():
            continue
        if arch:
            run("lipo", "-verify_arch", "arm64" if arch == "aarch64" else arch, path)
        if sys.platform == "darwin":
            # Homebrew/build-machine dependencies cannot be shipped as absolute paths.
            for line in run("otool", "-L", path).decode().splitlines():
                dependency = line.strip().split(" (", 1)[0]
                if dependency.startswith("/") and not dependency.endswith(":"):
                    if not dependency.startswith(("/System/Library/", "/usr/lib/")):
                        raise PackageError(f"Nonportable library dependency in {path.name}: {dependency}")
    return info


def sign_bundle(app, identity="-"):
    validate_bundle(app)
    run("xattr", "-cr", app)
    flags = ("--options", "0", "--timestamp=none") if identity == "-" else (
        "--options", "runtime", "--timestamp")
    # Sign nested code before its enclosing framework or app; --deep is verification-only.
    for path in [*bundle_code(app), app]:
        args = ["codesign", "--force", "--sign", identity, *flags]
        if path == app or path.parent == app / "Contents/MacOS":
            args.extend(("--entitlements", str(ENTITLEMENTS)))
        run(*args, path)
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", app)


def notarize(path):
    reply = run("xcrun", "notarytool", "submit", path, "--wait",
                "--output-format", "json",
                "--apple-id", os.environ["MACOS_APPLE_ID"],
                "--team-id", os.environ["MACOS_TEAM_ID"],
                "--password", os.environ["MACOS_APP_PASSWORD"])
    result = json.loads(reply)
    if result.get("status") != "Accepted":
        raise PackageError(f"Notarization rejected: submission {result.get('id')}, "
                           f"status {result.get('status')}")


def staple(path):
    run("xcrun", "stapler", "staple", path)
    run("xcrun", "stapler", "validate", path)


@contextmanager
def mount_dmg(dmg):
    with tempfile.TemporaryDirectory(prefix="ndisafe-mount-") as temporary:
        mount = Path(temporary) / "volume"
        run("hdiutil", "verify", dmg)
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
        try:
            yield mount
        finally:
            run("hdiutil", "detach", mount)


def verify_dmg(dmg, version, arch):
    with mount_dmg(dmg) as mount:
        apps = list(mount.glob("*.app"))
        if len(apps) != 1 or apps[0].name != APP_NAME:
            raise PackageError("DMG must contain exactly the NDISafe app at its root")
        applications = mount / "Applications"
        if not applications.is_symlink() or os.readlink(applications) != "/Applications":
            raise PackageError("DMG is missing the Applications shortcut")
        validate_bundle(apps[0], version, arch)
        run("codesign", "--verify", "--deep", "--strict", "--verbose=2", apps[0])


def verify_pkg(pkg, version, arch):
    with tempfile.TemporaryDirectory(prefix="ndisafe-pkg-check-") as temporary:
        expanded = Path(temporary) / "expanded"
        run("pkgutil", "--expand-full", pkg, expanded)
        payloads = [path for path in expanded.rglob("Payload") if path.is_dir()]
        if len(payloads) != 1:
            raise PackageError("Installer must contain exactly one application payload")
        contents = list(payloads[0].iterdir())
        if len(contents) != 1 or contents[0].name != APP_NAME:
            raise PackageError("Installer contains unrelated build output")
        validate_bundle(contents[0], version, arch)
        run("codesign", "--verify", "--deep", "--strict", "--verbose=2", contents[0])


def package(app, version, arch, output, finder=True):
    signed = signing_config()
    info = validate_bundle(app, version, arch)
    output.mkdir(parents=True, exist_ok=True)
    dmg = output / f"ndisafe-desk-{version}-{arch}.dmg"
    pkg = output / f"NDISafe-Desk-{version}-{arch}.pkg"
    if dmg.exists() or pkg.exists():
        raise PackageError("Installer output already exists; use a fresh output directory")
    with tempfile.TemporaryDirectory(prefix="ndisafe-package-") as temporary:
        work = Path(temporary)
        stage = work / "app-root"
        stage.mkdir()
        staged_app = stage / APP_NAME
        run("ditto", app, staged_app)
        identity = os.environ["MACOS_CODESIGN_IDENTITY"] if signed else "-"
        sign_bundle(staged_app, identity)
        version_output = run(staged_app / "Contents/MacOS/Ndisafe-desk", "--version")
        if version not in version_output.decode(errors="replace").splitlines():
            raise PackageError("Packaged application did not launch with the expected version")
        if signed:
            zipped = work / "app.zip"
            run("ditto", "-c", "-k", "--keepParent", staged_app, zipped)
            notarize(zipped)
            staple(staged_app)
            run("spctl", "--assess", "--type", "execute", "--verbose=2", staged_app)

        components = work / "components.plist"
        with components.open("wb") as dest:
            plistlib.dump([{
                "RootRelativeBundlePath": APP_NAME,
                "BundleIsRelocatable": False,
                "BundleIsVersionChecked": True,
                "BundleHasStrictIdentifier": True,
                "BundleOverwriteAction": "upgrade",
            }], dest)
        unsigned_pkg = work / "component.pkg"
        run("pkgbuild", "--root", stage, "--component-plist", components,
            "--identifier", BUNDLE_ID, "--version", version,
            "--install-location", "/Applications", "--ownership", "recommended", unsigned_pkg)
        if signed:
            run("productsign", "--sign", os.environ["MACOS_INSTALLER_IDENTITY"], unsigned_pkg, pkg)
            notarize(pkg)
            staple(pkg)
            run("pkgutil", "--check-signature", pkg)
            run("spctl", "--assess", "--type", "install", "--verbose=2", pkg)
        else:
            shutil.copy2(unsigned_pkg, pkg)
        verify_pkg(pkg, version, arch)

        # Stage contains the app, not the app's Contents directory or Xcode build products.
        readme = (
            "NDISafe Desk for macOS\n\n"
            "Drag Ndisafe-desk.app into Applications, then open it from Applications.\n"
            "Enable Screen Recording and Accessibility when requested for remote support.\n"
            "Camera and Microphone are only needed for calls.\n"
        )
        if not signed:
            readme += (
                "\nThis build has not been signed with an Apple Developer ID or notarized.\n"
                "macOS may request approval in System Settings > Privacy & Security.\n"
                "https://support.apple.com/102445\n"
            )
        (stage / "Install NDISafe Desk.txt").write_text(readme, encoding="utf-8")
        options = [] if finder else ["--skip-jenkins"]
        run("create-dmg", "--volname", "NDISafe Desk Installer",
            "--volicon", staged_app / "Contents/Resources/AppIcon.icns",
            "--filesystem", "HFS+", "--format", "UDZO", "--no-internet-enable",
            "--window-size", "800", "400", "--icon-size", "100",
            "--icon", APP_NAME, "200", "190", "--hide-extension", APP_NAME,
            "--app-drop-link", "600", "185", *options, dmg, stage)
        if signed:
            run("codesign", "--force", "--sign", identity, "--timestamp", dmg)
            notarize(dmg)
            staple(dmg)
            run("spctl", "--assess", "--type", "open",
                "--context", "context:primary-signature", "--verbose=2", dmg)
        verify_dmg(dmg, version, arch)

    manifest = {
        "version": version, "arch": arch, "bundle_id": BUNDLE_ID,
        "minimum_macos": info.get("LSMinimumSystemVersion"),
        "developer_id_signed": signed, "notarized": signed, "files": {},
    }
    for path in (dmg, pkg):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        path.with_suffix(path.suffix + ".sha256").write_text(
            f"{digest}  {path.name}\n", encoding="ascii")
        manifest["files"][path.name] = {"sha256": digest, "size": path.stat().st_size}
    (output / f"macos-{version}-{arch}.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    if not signed:
        print("::warning::macOS installers verified, but Apple Developer ID signing and "
              "notarization are not configured. macOS may require user approval.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("sign", "package", "check-signing"))
    parser.add_argument("--app", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--arch", choices=("x86_64", "aarch64"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.command == "check-signing":
        print("Developer ID" if signing_config() else "Ad-hoc test build (not notarized)")
        return
    if sys.platform != "darwin":
        parser.error("Installer creation and code signing require macOS")
    if not args.app:
        parser.error("--app is required")
    if args.command == "sign":
        sign_bundle(args.app.resolve())
    else:
        if not args.version or not args.arch or not args.output:
            parser.error("--version, --arch and --output are required")
        package(args.app.resolve(), args.version, args.arch, args.output.resolve())


if __name__ == "__main__":
    try:
        main()
    except (PackageError, OSError, ValueError) as error:
        print(f"macOS packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
