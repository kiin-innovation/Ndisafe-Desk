# In-app Windows updates (1.4.11)

Windows NDISafe Desk copies now offer Update without opening a browser.
An uninstalled EXE or ZIP first asks permission to install the new MSI.
Windows may request administrator approval. Installation-disabled builds
remain portable and retain the manual Download action.

MSI installs use the same MSI product identity as earlier releases, while
runtime configuration remains under NDISafe Desk. The first in-app install
imports the portable device configuration into the service account without
overwriting existing service configuration. No user configuration is deleted.

Auto update defaults to enabled for Windows NDISafe Desk. Explicit disabled
settings and managed configuration overrides are respected. The installed
server checks after 30 seconds, then daily, retrying failures or busy sessions
after 30 minutes. It defers installation while connections are active.
The Settings > Other > Auto update checkbox remains available.

## Bootstrap

Existing 1.4.9/1.4.10 binaries cannot acquire this UI change before upgrading.
Install the 1.4.11 MSI once. Keep that installation for the next stable release
test. The EXE asset is a portable launcher, not an installer merely by opening
it. Future release tags must match Cargo, Flutter, and workflow versions.

## Acceptance checks

1. Install the 1.4.11 MSI. Check installed status, service startup, device ID,
   password, peers, and the Auto update setting.
2. Publish the next genuine stable version with both Windows assets attached.
   With Auto update disabled, reopen 1.4.11 and press Update. Verify progress,
   installation, preserved configuration, and the new version without a browser.
3. Cancel the download, then retry. Double-click Update and check that only one
   update starts. Test offline download and denied Windows approval: errors
   should appear inside the application and allow another attempt.
4. Enable Auto update and repeat on an idle installed copy. Verify silent MSI
   installation in the installed system server and the new version on reopening.
   No PC reboot should be forced. Tray/UI restoration after silent MSI upgrades
   remains subject to the existing Windows installer behavior.
5. Keep a remote session, camera call, or transfer open through an automatic
   check. It must not install until idle; repeat with a session starting during
   download.
6. For an uninstalled 1.4.11 copy, publish the next release, press Update, and
   accept the first installation. Confirm its ID/password/options reach the
   installed service. Repeat with an existing service config: do not replace it.

Automated checks cover version/asset selection, native updater URL policy,
first-install config copying, and MSI identity/action configuration. Full
installed-client upgrade and UAC behavior still require these Windows tests.
