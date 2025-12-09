#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2025 Pavel Dubrova <pashadubrova@gmail.com>

# Exit immediately if a command exits with a non-zero status,
# Treat unset variables as an error, and propagate errors in pipelines
set -euo pipefail

# Trap Ctrl+C and give a friendly message
trap 'echo -e "\n${0##*/} execution was interrupted by Ctrl+C."; exit 1' SIGINT

# --------------------------
# Configuration
# --------------------------
SRC_DIR="src"
OUT_DIR="out"

REPO_SRC="git@github.com:bartcubbins/openwrt.git"
RELEASE="openwrt-24.10"

CUSTOM_FEED="https://github.com/bartcubbins/openwrt-archer-c6-v2-custom-feed.git"
FEED_LINE="src-git customfeed $CUSTOM_FEED"
DIFFCONFIG="archer-c6-v2.diffconfig"

# Ensure output directory exists and is empty
if [ -d "$OUT_DIR" ]; then
    rm -rf "$OUT_DIR"/*
else
    mkdir -p "$OUT_DIR"
fi

# --------------------------
# Clone or update OpenWrt source
# --------------------------
echo "----------------------------------------"
if [ ! -d "$SRC_DIR" ]; then
    echo "[1/9] Cloning OpenWrt repository..."
    git clone --branch "$RELEASE" "$REPO_SRC" "$SRC_DIR"
else
    echo "[1/8] Updating existing OpenWrt repository..."
    cd "$SRC_DIR"
    git fetch --all
    git checkout "$RELEASE"
    cd ..
fi

cd "$SRC_DIR"

# --------------------------
# Update and install feeds
# --------------------------
echo "----------------------------------------"
echo "[2/8] Updating and installing feeds..."

# Add custom feed if not already present
if ! grep -qxF "$FEED_LINE" feeds.conf.default; then
    echo "$FEED_LINE" >> feeds.conf.default
    echo "Custom feed added to feeds.conf.default"
fi

./scripts/feeds update -a
./scripts/feeds install -a

# --------------------------
# Configure target, packages, modules
# --------------------------
echo "----------------------------------------"
echo "[3/8] Applying custom defconfig..."
if [ -f "../$DIFFCONFIG" ]; then
    cp "../$DIFFCONFIG" .config
else
    echo "Error: Diffconfig $DIFFCONFIG not found!" >&2
    exit 1
fi
make defconfig

echo "----------------------------------------"
echo "[4/8] Downloading all source files..."
make download

echo "----------------------------------------"
echo "[5/8] Building firmware..."
make -j"$(nproc)" V=s

cd ..

# --------------------------
# Copy firmware to output directory
# --------------------------
echo "----------------------------------------"
echo "[6/8] Copying firmware to $OUT_DIR..."
cp $SRC_DIR/bin/targets/ath79/generic/*.bin "$OUT_DIR"

echo "----------------------------------------"
echo "[7/8] Firmware files in $OUT_DIR:"
ls -1 "$OUT_DIR"

# --------------------------
# Create release info
# --------------------------
echo "----------------------------------------"
echo "[7/8] Writing release-info..."

RELEASE_INFO="$OUT_DIR/release-info.txt"

OWRT_COMMIT=$(git -C "$SRC_DIR" rev-parse --short HEAD)
OWRT_COMMIT_MSG=$(git -C "$SRC_DIR" log -1 --pretty=%B)
OWRT_COMMIT_DATE=$(git -C "$SRC_DIR" log -1 --date=iso --pretty=%cd)

FEED_DIR="$SRC_DIR/feeds/customfeed"

if [ -d "$FEED_DIR" ]; then
    FEED_COMMIT=$(git -C "$FEED_DIR" rev-parse --short HEAD)
    FEED_COMMIT_MSG=$(git -C "$FEED_DIR" log -1 --pretty=%s)
    FEED_COMMIT_DATE=$(git -C "$FEED_DIR" log -1 --date=iso --pretty=%cd)
else
    FEED_COMMIT="N/A"
    FEED_COMMIT_MSG="Directory not found"
    FEED_COMMIT_DATE="N/A"
fi

cat > "$RELEASE_INFO" <<EOF
OpenWrt Build Release Info
==========================

Build Time:
  $(date -Iseconds)

OpenWrt Source:
  Branch: $RELEASE
  Commit: $OWRT_COMMIT
  Date:   $OWRT_COMMIT_DATE
  Message:
    $OWRT_COMMIT_MSG

Custom Feed:
  URL: $CUSTOM_FEED
  Commit: $FEED_COMMIT
  Date:   $FEED_COMMIT_DATE
  Message:
    $FEED_COMMIT_MSG

Firmware Files:
$(ls -1 "$OUT_DIR"/*.bin 2>/dev/null | sed 's/^/  /')
EOF

# --------------------------
# GitHub release and Push
# --------------------------
echo "----------------------------------------"
echo "[8/8] Build finished."
echo "Do you want to create and push a GitHub release? (y/n)"
read -r CREATE_TAG

if [[ "$CREATE_TAG" =~ ^[Yy]$ ]]; then
    echo "Creating GitHub release..."

    TAG="build-$(date +%Y%m%d-%H%M)"

    # Create GitHub release with assets and release-info.txt as description
    gh release create "$TAG" "$OUT_DIR"/*.bin \
        --title "OpenWrt Firmware $TAG" \
        --notes-file "$RELEASE_INFO"

    echo "GitHub release created and assets uploaded."
else
    echo "Skipping GitHub release creation."
fi

echo "----------------------------------------"
echo "Done."
