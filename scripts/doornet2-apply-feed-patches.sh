#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMPDIR_DEFAULT="$ROOT_DIR/tmp"

cd "$ROOT_DIR"
mkdir -p "$TMPDIR_DEFAULT"
export TMPDIR="${TMPDIR:-$TMPDIR_DEFAULT}"

apply_patch_file() {
	local patch_file="$1"
	local required_file="$2"
	local label="$3"

	if [ ! -f "$patch_file" ]; then
		echo "missing patch file: $patch_file" >&2
		exit 1
	fi

	if [ ! -f "$required_file" ]; then
		echo "required file not found: $required_file" >&2
		echo "run ./scripts/feeds update/install before applying local feed patches" >&2
		exit 1
	fi

	if patch -p1 -R --dry-run --batch < "$patch_file" >/dev/null 2>&1; then
		echo "$label already applied"
		return
	fi

	if ! patch -p1 --dry-run --batch < "$patch_file" >/dev/null 2>&1; then
		echo "failed to apply $label cleanly" >&2
		exit 1
	fi

	patch -p1 --batch < "$patch_file"
	echo "applied $label"
}

sync_file() {
	local source_file="$1"
	local target_file="$2"
	local label="$3"

	if [ ! -f "$source_file" ]; then
		echo "missing source file: $source_file" >&2
		exit 1
	fi

	mkdir -p "$(dirname "$target_file")"

	if [ -f "$target_file" ]; then
		if cmp -s "$source_file" "$target_file"; then
			echo "$label already synced"
			return
		fi

		echo "target file differs from expected content: $target_file" >&2
		exit 1
	fi

	cp "$source_file" "$target_file"
	echo "synced $label"
}

apply_patch_file \
	"$ROOT_DIR/scripts/patches/istore-luci-app-store-apk.patch" \
	"$ROOT_DIR/feeds/istore/luci/luci-app-store/Makefile" \
	"istore feed patch"

apply_patch_file \
	"$ROOT_DIR/scripts/patches/feeds-packages-golang-path-quote.patch" \
	"$ROOT_DIR/feeds/packages/lang/golang/golang-package.mk" \
	"feeds/packages golang PATH quoting patch"

apply_patch_file \
	"$ROOT_DIR/scripts/patches/feeds-packages-netdata-makefile.patch" \
	"$ROOT_DIR/feeds/packages/admin/netdata/Makefile" \
	"feeds/packages netdata Makefile patch"

sync_file \
	"$ROOT_DIR/scripts/patches/netdata-005-require-cxx14-for-protobuf-absl.patch" \
	"$ROOT_DIR/feeds/packages/admin/netdata/patches/005-require-cxx14-for-protobuf-absl.patch" \
	"feeds/packages netdata C++14 compatibility patch"
