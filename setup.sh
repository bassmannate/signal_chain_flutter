#!/usr/bin/env bash
set -e

echo "=== Setting up Signal Chain Flutter Environment ==="

if ! command -v flutter &> /dev/null; then
    echo "Error: Flutter SDK is not installed or not in your PATH."
    exit 1
fi

echo "-> Installing system build dependencies (requires sudo)..."
sudo apt-get update -y
sudo apt-get install -y \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-14-dev

echo "-> Fetching project dependencies..."
flutter pub get

echo "=== Setup complete! Run 'flutter run -d linux' to launch the app. ==="
