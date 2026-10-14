# macOS installers

The app is installed at /Applications/Ndisafe-desk.app. Its display name is
NDISafe Desk and its bundle identifier is com.ndisafe.desk. The bundle name and
executable deliberately keep the same spelling as previous NDISafe installers.
Preferences remain in the existing NDISafe Desk configuration directory.

Use the aarch64 download for Apple Silicon (M-series) Macs, requiring macOS 12.3
or later. Use x86_64 for Intel Macs, requiring macOS 10.14 or later.

## Fixes in 1.4.13

- Replace the macOS app, disk-volume, menu-bar and in-app RustDesk icons with the
  checked-in NDISafe artwork.
- Sign the complete app after copying the Rust service helper into its bundle.
- Stage only the app for PKG installation; do not install the Xcode products
  directory or relocate an upgrade onto a copy running from a mounted DMG.
- Build a compressed HFS+ disk image from a staging folder containing the app,
  an Applications shortcut and installation notes.
- Verify image integrity, mount the finished DMG, verify its app signature, and
  unpack the PKG to verify its contents before uploading either installer.
- Check release version, processor architecture, linked libraries, icon and
  camera/microphone permission descriptions.
- Align native service and updater paths with Ndisafe-desk.app while preserving
  existing preferences and IPC socket names.
- Publish a SHA-256 sidecar for each installer and a JSON verification manifest.

The new bundle identity separates NDISafe from RustDesk. macOS may ask users to
grant Screen Recording, Accessibility, Microphone and Camera permissions again.

## Apple signing setup

The repository can create integrity-checked, ad-hoc-signed builds without an
Apple account. These are NOT Developer ID signed or notarized: macOS may require
explicit user approval. Validating a DMG does not remove Gatekeeper requirements.
Do not advertise these builds as notarized.

For normal public distribution, an Apple Developer team owner must configure
these GitHub Actions secrets:

| Secret | Value |
| --- | --- |
| MACOS_P12_BASE64 | Base64-encoded PKCS#12 containing the Developer ID Application and Developer ID Installer certificates and their private keys |
| MACOS_P12_PASSWORD | Password protecting that PKCS#12 |
| MACOS_CODESIGN_IDENTITY | Full Developer ID Application certificate identity |
| MACOS_INSTALLER_IDENTITY | Full Developer ID Installer certificate identity |
| MACOS_APPLE_ID | Apple ID used for notarization |
| MACOS_TEAM_ID | Apple Developer team ID |
| MACOS_APP_PASSWORD | Apple app-specific password for notarization |

Never commit certificates or passwords. The workflow imports the certificates
into the runner's temporary keychain. With all secrets present, it signs nested
code from the inside out, notarizes/staples the app and both installers, and
requires successful Gatekeeper assessment. Partial configuration fails the build.

References:
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- https://developer.apple.com/library/archive/technotes/tn2206/_index.html
- https://support.apple.com/102445

## Validation

Local cross-platform checks:

```sh
python -m unittest discover -s tools -p test_macos_package.py -v
rustc --edition=2021 --test src/platform/macos_install.rs -o macos-install-tests
./macos-install-tests
```

On macOS, the Python suite also compiles a small native fixture and exercises real
codesign, DMG creation/mounting and PKG extraction. The build workflow runs this
on both Intel and Apple Silicon, then validates the actual release app separately.

For a downloaded installer, compare its checksum with the matching .sha256 file
and run hdiutil verify on the DMG. A checksum mismatch indicates a different or
incomplete download. Do not work around a failed signature or damaged-image check
by disabling Gatekeeper or removing quarantine attributes.

For an integrity-checked build without Developer ID, follow Apple's documented
Privacy & Security approval process if macOS offers it. A warning-free public
installation still requires the Apple signing setup above.

Manual acceptance: open the downloaded DMG, drag the app into Applications,
eject the image, launch the installed app, grant the requested support permissions,
test camera and microphone calls, enable the service, and restart the Mac.
Verify the icon in Finder, Dock, menu bar and the app itself. Also test upgrading
an existing installation without losing its ID or settings.
