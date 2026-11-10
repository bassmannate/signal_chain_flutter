#!/usr/bin/env bash
set -e

echo "=== Setting up Signal Chain Flutter Environment ==="

# 1. Verify Flutter SDK is available
if ! command -v flutter &> /dev/null; then
    echo "Error: Flutter SDK is not installed or not in your PATH."
    echo "Please install Flutter first: https://docs.flutter.dev/get-started/install/linux"
    exit 1
fi

echo "-> Flutter SDK detected at $(which flutter)"

# 2. Install system-level build tools and GTK development headers for Linux desktop
echo "-> Installing system build dependencies (requires sudo)..."
sudo apt-get update -y
sudo apt-get install -y \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev

# 3. Fetch Flutter/Dart packages
echo "-> Fetching project dependencies..."
flutter pub get

# 4. Run Flutter doctor to verify setup
echo "-> Running flutter doctor verification..."
flutter doctor -v

echo "=== Setup complete! Run 'flutter run -d linux' to launch the app. ==="
