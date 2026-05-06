#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH_FILE="$ROOT_DIR/scripts/patches/istore-luci-app-store-apk.patch"

cd "$ROOT_DIR"

if [ ! -f "$PATCH_FILE" ]; then
	echo "missing patch file: $PATCH_FILE" >&2
	exit 1
fi

if [ ! -f "$ROOT_DIR/feeds/istore/luci/luci-app-store/Makefile" ]; then
	echo "feeds/istore/luci/luci-app-store/Makefile not found" >&2
	echo "run ./scripts/feeds update/install before applying local feed patches" >&2
	exit 1
fi

if patch -p1 -R --dry-run < "$PATCH_FILE" >/dev/null 2>&1; then
	echo "istore feed patch already applied"
	exit 0
fi

patch -p1 < "$PATCH_FILE"
echo "applied istore feed patch"
