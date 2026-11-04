#!/usr/bin/env bash
set -e

echo "=========================================="
echo "  Deploying GPS Land Measure to Render"
echo "=========================================="

# 1. Download & cache Flutter stable if not already present
if [ ! -d "_flutter" ]; then
  echo ">>> Cloning Flutter SDK (stable branch)..."
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable _flutter
else
  echo ">>> Flutter SDK already cached."
fi

# 2. Add Flutter to PATH
export PATH="$PATH:`pwd`/_flutter/bin"

# 3. Disable telemetry & check version
flutter config --no-analytics
flutter --version

# 4. Get dependencies & build release web bundle
echo ">>> Resolving dependencies..."
flutter pub get

echo ">>> Building Flutter Web bundle..."
flutter build web --release

echo "=========================================="
echo "  Build successful! Ready for Render."
echo "=========================================="

