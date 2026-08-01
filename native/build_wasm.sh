#!/usr/bin/env bash
# native/build_wasm.sh
#
# Builds the Rust crypto_core crate as a WebAssembly module using wasm-pack
# and copies the output into app/web/pkg/ so Flutter Web can load it.
#
# Usage (from repo root):
#   bash native/build_wasm.sh
#
# Prerequisites:
#   - Rust toolchain with wasm32-unknown-unknown target:
#       rustup target add wasm32-unknown-unknown
#   - wasm-pack:
#       cargo install wasm-pack --locked
#
# Output written to app/web/pkg/:
#   crypto_core.js        — JS glue that loads and initialises the WASM module
#   crypto_core_bg.wasm   — the compiled WebAssembly binary
#   crypto_core.d.ts      — TypeScript declarations (not used by Dart, but useful)
#   package.json          — wasm-pack metadata (ignored at runtime)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="${REPO_ROOT}/native/crypto_core"
OUT_DIR="${REPO_ROOT}/app/web/pkg"

echo "==> Building crypto_core WASM bundle..."
echo "    Crate : ${CRATE_DIR}"
echo "    Output: ${OUT_DIR}"

# wasm-pack build --target web generates an ES-module-style glue file that
# must be initialised via its exported init() function before any crypto
# function is called. The --features wasm flag activates wasm-bindgen exports
# and the browser entropy sources (getrandom/js, getrandom-v04/wasm_js).
wasm-pack build \
  --target web \
  --out-dir "${OUT_DIR}" \
  --release \
  "${CRATE_DIR}" \
  -- \
  --features wasm

echo "==> WASM build complete."
echo "    Files in ${OUT_DIR}:"
ls -lh "${OUT_DIR}/"*.{js,wasm} 2>/dev/null || true
