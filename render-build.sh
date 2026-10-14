#!/usr/bin/env bash
# Render Build Command for Browser.js.
# Add this file to the root of your fork, then set Render's Build Command to:
#   bash render-build.sh
set -euo pipefail

# ---- 0. pnpm -------------------------------------------------------------
# Render's preinstalled pnpm may not match the pinned version in package.json
# ("packageManager": "pnpm@10.12.1"), which makes pnpm abort with
# ERR_PNPM_BAD_PM_VERSION. npx fetches the exact pinned version, and unlike
# `corepack enable` it works on Render's read-only /usr/bin.
PNPM="npx --yes pnpm@10.12.1"

# ---- 1. submodules -------------------------------------------------------
# external/dreamlandjs is required (packages/chrome depends on `dreamland`).
# external/playwright is NOT - it is only used by the runway test suite and is
# a huge checkout, so we deliberately skip it.
git submodule update --init external/dreamlandjs

# ---- 2. dependencies -----------------------------------------------------
# Dev dependencies must be installed: rspack/vite build the app and
# @mercuryworkshop/wisp-js is what render-server.mjs uses at runtime.
$PNPM install

# ---- 3. the Rust rewriter (scramjet.wasm) --------------------------------
# packages/scramjet/packages/core/dist/ is gitignored and normally produced by
# a Rust nightly + wasm-bindgen + binaryen + wasm-snip toolchain
# (rewriter/wasm/build.sh). Render's Node image has no Rust, so instead we pull
# the prebuilt dist published to npm for the exact version in the repo.
CORE="packages/scramjet/packages/core"
VER=$(node -p "require('./$CORE/package.json').version")
echo "Fetching prebuilt scramjet dist for v$VER"
mkdir -p "$CORE/dist"
TMP=$(mktemp -d)
curl -fsSL "https://registry.npmjs.org/@mercuryworkshop/scramjet/-/scramjet-${VER}.tgz" -o "$TMP/sj.tgz"
tar xzf "$TMP/sj.tgz" -C "$TMP"
cp -r "$TMP/package/dist/." "$CORE/dist/"
rm -rf "$TMP"
test -f "$CORE/dist/scramjet.wasm" || { echo "scramjet.wasm missing"; exit 1; }

# ---- 4. build ------------------------------------------------------------
$PNPM build:dreamland

# SKIP_CORE=1 skips rebuilding scramjet from source. Without it, rspack
# compiles every scramjet bundle in one process and gets OOM-killed on small
# instances (exit 137). We already have the prebuilt dist from step 3, so this
# only builds the two things the frontend actually imports from the workspace:
# packages/cdp (chobitsu) and packages/inject (included via ?url).
SKIP_CORE=1 $PNPM build

# Vite inlines these at build time - set them as Render env vars.
#   VITE_WISP_URL          wss://<your-service>.onrender.com/
#   VITE_ISOLATION_ORIGIN  none  (or a separate sandbox origin)
export VITE_ISOLATION_ORIGIN="${VITE_ISOLATION_ORIGIN:-none}"
$PNPM build:chrome

echo "Build complete -> packages/chrome/dist"
