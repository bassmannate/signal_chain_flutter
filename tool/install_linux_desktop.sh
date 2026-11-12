#!/usr/bin/env bash
set -euo pipefail

# Install/Update Signal Chain desktop application into current user's profile
# Location: ~/.local/bin and ~/.local/share
# No sudo/root required.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PACKAGE_NAME="signal-chain"
APP_INSTALL_DIR="${HOME}/.local/lib/${PACKAGE_NAME}"
BIN_DIR="${HOME}/.local/bin"
DESKTOP_DIR="${HOME}/.local/share/applications"
ICON_DIR_SCALABLE="${HOME}/.local/share/icons/hicolor/scalable/apps"
ICON_DIR_PNG="${HOME}/.local/share/icons/hicolor/256x256/apps"
BUILD_OUTPUT="${PROJECT_ROOT}/build/linux/x64/release/bundle"

echo "=== Installing Signal Chain to ~/.local ==="

# 1. Build if not present
if [ ! -d "${BUILD_OUTPUT}" ]; then
  echo "Release bundle not found. Building release bundle..."
  (cd "${PROJECT_ROOT}" && flutter build linux --release)
fi

# 2. Create destination directories
mkdir -p "${APP_INSTALL_DIR}"
mkdir -p "${BIN_DIR}"
mkdir -p "${DESKTOP_DIR}"
mkdir -p "${ICON_DIR_SCALABLE}"
mkdir -p "${ICON_DIR_PNG}"

# 3. Synchronize bundle files
echo "Installing application bundle to ${APP_INSTALL_DIR}..."
rm -rf "${APP_INSTALL_DIR:?}"/*
cp -r "${BUILD_OUTPUT}"/* "${APP_INSTALL_DIR}/"

# 4. Create launcher script in ~/.local/bin
cat <<EOF > "${BIN_DIR}/${PACKAGE_NAME}"
#!/usr/bin/env bash
exec "${APP_INSTALL_DIR}/signal_chain_flutter" "\$@"
EOF
chmod +x "${BIN_DIR}/${PACKAGE_NAME}"

# 5. Install desktop entry and icons
DESKTOP_FILE="${PROJECT_ROOT}/linux/packaging/signal-chain.desktop"
if [ -f "${DESKTOP_FILE}" ]; then
  # Ensure Exec points to user local bin or executable
  sed "s|^Exec=signal-chain|Exec=${BIN_DIR}/${PACKAGE_NAME}|g" "${DESKTOP_FILE}" > "${DESKTOP_DIR}/signal-chain.desktop"
  chmod +x "${DESKTOP_DIR}/signal-chain.desktop"
fi

if [ -f "${PROJECT_ROOT}/linux/packaging/signal-chain.svg" ]; then
  cp "${PROJECT_ROOT}/linux/packaging/signal-chain.svg" "${ICON_DIR_SCALABLE}/signal-chain.svg"
fi
if [ -f "${PROJECT_ROOT}/linux/packaging/signal-chain.png" ]; then
  cp "${PROJECT_ROOT}/linux/packaging/signal-chain.png" "${ICON_DIR_PNG}/signal-chain.png"
fi

# 6. Refresh icon cache and desktop database if available
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${DESKTOP_DIR}" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "=== Successfully installed Signal Chain! ==="
echo "Launcher binary: ${BIN_DIR}/${PACKAGE_NAME}"
echo "Desktop entry:   ${DESKTOP_DIR}/signal-chain.desktop"
echo ""
echo "Note: Ensure '${BIN_DIR}' is in your PATH to run 'signal-chain' from any terminal."

