#!/usr/bin/env bash
set -euo pipefail

# Package Linux Debian (.deb) package for Signal Chain
# Usage: ./tool/package_linux_deb.sh [version]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-1.0.0}"
ARCH="amd64"
PACKAGE_NAME="signal-chain"
DEB_DIR_NAME="${PACKAGE_NAME}_${VERSION}_${ARCH}"
BUILD_OUTPUT="${PROJECT_ROOT}/build/linux/x64/release/bundle"
DIST_DIR="${PROJECT_ROOT}/dist"
PKG_ROOT="${DIST_DIR}/${DEB_DIR_NAME}"

echo "=== Building Signal Chain Debian Package (${VERSION}) ==="

# Check build output
if [ ! -d "${BUILD_OUTPUT}" ]; then
  echo "Release bundle not found at ${BUILD_OUTPUT}."
  echo "Building release bundle..."
  (cd "${PROJECT_ROOT}" && flutter build linux --release)
fi

# Clean and prepare package directory
rm -rf "${PKG_ROOT}"
mkdir -p "${PKG_ROOT}/DEBIAN"
mkdir -p "${PKG_ROOT}/usr/lib/${PACKAGE_NAME}"
mkdir -p "${PKG_ROOT}/usr/bin"
mkdir -p "${PKG_ROOT}/usr/share/applications"
mkdir -p "${PKG_ROOT}/usr/share/icons/hicolor/scalable/apps"
mkdir -p "${PKG_ROOT}/usr/share/icons/hicolor/256x256/apps"

# 1. Copy bundle assets to /usr/lib/signal-chain
cp -r "${BUILD_OUTPUT}"/* "${PKG_ROOT}/usr/lib/${PACKAGE_NAME}/"

# 2. Create launcher symlink in /usr/bin
ln -sf "/usr/lib/${PACKAGE_NAME}/signal_chain_flutter" "${PKG_ROOT}/usr/bin/${PACKAGE_NAME}"

# 3. Copy desktop entry
cp "${PROJECT_ROOT}/linux/packaging/signal-chain.desktop" "${PKG_ROOT}/usr/share/applications/"

# 4. Copy icons
if [ -f "${PROJECT_ROOT}/linux/packaging/signal-chain.svg" ]; then
  cp "${PROJECT_ROOT}/linux/packaging/signal-chain.svg" "${PKG_ROOT}/usr/share/icons/hicolor/scalable/apps/signal-chain.svg"
fi
if [ -f "${PROJECT_ROOT}/linux/packaging/signal-chain.png" ]; then
  cp "${PROJECT_ROOT}/linux/packaging/signal-chain.png" "${PKG_ROOT}/usr/share/icons/hicolor/256x256/apps/signal-chain.png"
fi

# Calculate installed size in KB
INSTALLED_SIZE=$(du -sk "${PKG_ROOT}/usr" | cut -f1)

# 5. Create DEBIAN/control file with alsa-utils dependency for amidi
cat <<EOF > "${PKG_ROOT}/DEBIAN/control"
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Section: sound
Priority: optional
Architecture: ${ARCH}
Depends: alsa-utils, libgtk-3-0
Maintainer: Signal Chain Contributors <info@signal-chain.local>
Installed-Size: ${INSTALLED_SIZE}
Description: Signal Chain Multi-FX Patch Editor & Librarian
 Real-time patch editor, library manager, and bank reorganization tool
 for Zoom MS Plus series pedals and Line 6 Bass Pod Pro rackmount units.
 Requires alsa-utils (amidi) for zero-dependency Linux ALSA RawMIDI transport.
EOF

# 6. Build the debian package
echo "Packaging Debian archive via dpkg-deb..."
dpkg-deb --build --root-owner-group "${PKG_ROOT}" "${DIST_DIR}/${DEB_DIR_NAME}.deb"

echo "=== Successfully built Debian package: ${DIST_DIR}/${DEB_DIR_NAME}.deb ==="

