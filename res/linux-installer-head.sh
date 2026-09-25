#!/bin/sh
# NDISafe Desk self-extracting installer for Linux.
# No root required: installs into $HOME/.local.
# Usage: sh NDISafe-Desk-<version>-linux-installer.sh
set -e

APP_NAME="ndisafe-desk"
DISPLAY_NAME="NDISafe Desk"
DEST="${HOME}/.local/${APP_NAME}"
TMPDIR="$(mktemp -d)"

cleanup() {
    rm -rf "${TMPDIR}"
}
trap cleanup EXIT INT TERM

echo "Installing ${DISPLAY_NAME} to ${DEST} ..."

ARCHIVE_LINE=$(awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit 0;}' "$0")
if [ -z "${ARCHIVE_LINE}" ]; then
    echo "ERROR: embedded archive marker not found." >&2
    exit 1
fi

mkdir -p "${TMPDIR}/pkg"
tail -n +"${ARCHIVE_LINE}" "$0" | tar -xzf - -C "${TMPDIR}/pkg"

if [ ! -x "${TMPDIR}/pkg/${APP_NAME}" ]; then
    echo "ERROR: extracted bundle has no ${APP_NAME} binary." >&2
    exit 1
fi

rm -rf "${DEST}"
mkdir -p "${DEST}"
cp -r "${TMPDIR}/pkg/." "${DEST}/"
chmod +x "${DEST}/${APP_NAME}"

mkdir -p "${HOME}/.local/share/applications" "${HOME}/.local/share/icons"
sed "s|^Exec=.*|Exec=${DEST}/${APP_NAME} %u|" "${DEST}/${APP_NAME}.desktop" \
    > "${HOME}/.local/share/applications/${APP_NAME}.desktop"
cp "${DEST}/${APP_NAME}.png" "${HOME}/.local/share/icons/" 2>/dev/null || true
cp "${DEST}/${APP_NAME}.svg" "${HOME}/.local/share/icons/" 2>/dev/null || true
command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "${HOME}/.local/share/applications" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 \
    && gtk-update-icon-cache -f "${HOME}/.local/share/icons" || true

echo ""
echo "${DISPLAY_NAME} installed."
echo "  Run:   ${DEST}/${APP_NAME}"
echo "  Or find '${DISPLAY_NAME}' in your applications menu."
echo "  (Same system libraries as the portable tarball apply:"
echo "   gtk3, pulseaudio, gstreamer, libxdo on Debian/Ubuntu.)"
exit 0

__ARCHIVE_BELOW__
