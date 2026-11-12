#!/usr/bin/env bash
set -euo pipefail

# Package Linux AppImage for Signal Chain
# Usage: ./tool/package_linux_appimage.sh [version]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-1.0.0}"
PACKAGE_NAME="signal-chain"
BUILD_OUTPUT="${PROJECT_ROOT}/build/linux/x64/release/bundle"
DIST_DIR="${PROJECT_ROOT}/dist"
APPDIR="${DIST_DIR}/AppDir"

echo "=== Building Signal Chain AppImage (${VERSION}) ==="

# Check build output
if [ ! -d "${BUILD_OUTPUT}" ]; then
  echo "Release bundle not found at ${BUILD_OUTPUT}."
  echo "Building release bundle..."
  (cd "${PROJECT_ROOT}" && flutter build linux --release)
fi

# Clean and prepare AppDir
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/lib"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/metainfo"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/scalable/apps"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

# 1. Copy bundle assets into AppDir/usr/bin
cp -r "${BUILD_OUTPUT}"/* "${APPDIR}/usr/bin/"

# 2. Desktop entry, AppStream metainfo, and icons in root and standard locations
cp "${PROJECT_ROOT}/linux/packaging/signal-chain.desktop" "${APPDIR}/"
cp "${PROJECT_ROOT}/linux/packaging/signal-chain.desktop" "${APPDIR}/usr/share/applications/"

if [ -f "${PROJECT_ROOT}/linux/packaging/io.github.bassmannate.signal_chain.appdata.xml" ]; then
  cp "${PROJECT_ROOT}/linux/packaging/io.github.bassmannate.signal_chain.appdata.xml" "${APPDIR}/usr/share/metainfo/"
fi

if [ -f "${PROJECT_ROOT}/linux/packaging/signal-chain.svg" ]; then
  cp "${PROJECT_ROOT}/linux/packaging/signal-chain.svg" "${APPDIR}/usr/share/icons/hicolor/scalable/apps/signal-chain.svg"
fi
if [ -f "${PROJECT_ROOT}/linux/packaging/signal-chain.png" ]; then
  cp "${PROJECT_ROOT}/linux/packaging/signal-chain.png" "${APPDIR}/signal-chain.png"
  cp "${PROJECT_ROOT}/linux/packaging/signal-chain.png" "${APPDIR}/.DirIcon"
  cp "${PROJECT_ROOT}/linux/packaging/signal-chain.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/signal-chain.png"
fi

# 3. Create AppRun script
cat <<'EOF' > "${APPDIR}/AppRun"
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/usr/bin/signal_chain_flutter" "$@"
EOF
chmod +x "${APPDIR}/AppRun"

# 4. Check for or acquire appimagetool
APPIMAGETOOL="${APPIMAGETOOL:-}"
if [ -z "${APPIMAGETOOL}" ]; then
  if command -v appimagetool >/dev/null 2>&1; then
    APPIMAGETOOL="$(command -v appimagetool)"
  elif [ -x "${PROJECT_ROOT}/tool/appimagetool" ]; then
    APPIMAGETOOL="${PROJECT_ROOT}/tool/appimagetool"
  fi
fi

TARGET_APPIMAGE="${DIST_DIR}/${PACKAGE_NAME}-${VERSION}-x86_64.AppImage"

if [ -n "${APPIMAGETOOL}" ] && [ -x "${APPIMAGETOOL}" ]; then
  echo "Invoking appimagetool..."
  ARCH=x86_64 "${APPIMAGETOOL}" "${APPDIR}" "${TARGET_APPIMAGE}"
  echo "=== Successfully generated AppImage: ${TARGET_APPIMAGE} ==="
else
  echo "NOTE: 'appimagetool' was not found on PATH or at tool/appimagetool."
  echo "The AppDir structure has been assembled at: ${APPDIR}"
  echo "To finish packing, install appimagetool or download it from:"
  echo "  https://github.com/AppImage/appimagetool/releases"
  echo "Then run: ARCH=x86_64 appimagetool \"${APPDIR}\" \"${TARGET_APPIMAGE}\""
fi

