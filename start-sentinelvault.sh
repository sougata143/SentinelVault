#!/usr/bin/env bash
#
# SentinelVault — Local Dev Startup Script (macOS)
#
# Automates RUNNING_LOCALLY.md: prerequisite checks, dependency install,
# Docker infra (Postgres + Redis), the Rust crypto core build (native +
# wasm), the four backend services (run in the background with logs),
# and finally launches the Flutter app in the foreground.
#
# Place this script at the SentinelVault repo root (same level as app/,
# backend/, native/, docker-compose.yml) and run:
#
#   chmod +x start-sentinelvault.sh
#   ./start-sentinelvault.sh
#
# Options:
#   --check          Only verify prerequisites are installed, then exit
#   --skip-install   Skip npm install / flutter pub get steps
#   --skip-rust      Skip building the Rust crypto core (native + wasm)
#   --skip-docker    Skip starting Postgres/Redis via Docker Compose
#   --backend-only   Start infra + backend services, skip launching Flutter
#   --device NAME    Run Flutter directly on this device (e.g. chrome,
#                    macos, "iPhone 16", emulator-5554) instead of prompting
#   --help           Show this help text
#
# Stopping everything: ./stop-sentinelvault.sh (companion script)
#
# Security reminder: the Master Password never leaves the device. This
# script never logs, prints, or transmits it — nor should anything you add
# to it. Backend service logs land in .sentinelvault/logs/ (gitignored);
# do not add master-password or vault-content logging there.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$ROOT_DIR/.sentinelvault"
LOG_DIR="$STATE_DIR/logs"
PID_FILE="$STATE_DIR/pids"

mkdir -p "$LOG_DIR"
: > "$PID_FILE"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
CHECK_ONLY=false
SKIP_INSTALL=false
SKIP_RUST=false
SKIP_DOCKER=false
BACKEND_ONLY=false
DEVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --skip-install) SKIP_INSTALL=true; shift ;;
    --skip-rust) SKIP_RUST=true; shift ;;
    --skip-docker) SKIP_DOCKER=true; shift ;;
    --backend-only) BACKEND_ONLY=true; shift ;;
    --device) DEVICE="${2:-}"; shift 2 ;;
    --help)
      grep '^#' "$0" | sed 's/^#$//; s/^# //'
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (see --help)"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
c_green()  { printf "\033[0;32m%s\033[0m\n" "$1"; }
c_red()    { printf "\033[0;31m%s\033[0m\n" "$1"; }
c_yellow() { printf "\033[0;33m%s\033[0m\n" "$1"; }

require_cmd() {
  local cmd="$1" hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    c_red "✗ $cmd not found — $hint"
    return 1
  fi
  local ver
  ver="$($cmd --version 2>&1 | head -n1)"
  c_green "✓ $cmd found ($ver)"
  return 0
}

wait_for_health() {
  # Tries the HTTP /health endpoint first; if that never returns a 2xx
  # (e.g. the endpoint isn't implemented yet and 404s, or is slow to
  # register routes), falls back to a plain TCP port-open check so a
  # missing/unimplemented health route doesn't block the whole script.
  local url="$1" name="$2" port="$3" tries=30 i

  for ((i = 1; i <= tries; i++)); do
    if curl -sf "$url" >/dev/null 2>&1; then
      c_green "✓ $name is up ($url)"
      return 0
    fi
    sleep 1
  done

  c_yellow "⚠ $name: $url did not return a healthy response after ${tries}s."
  c_yellow "  Falling back to a plain TCP check on port $port..."

  if nc -z -w 2 localhost "$port" >/dev/null 2>&1; then
    c_yellow "✓ $name: port $port is open, so the process is running —"
    c_yellow "  but /health either isn't implemented or isn't returning 2xx."
    c_yellow "  Check $LOG_DIR/$name.log and consider adding a real health"
    c_yellow "  endpoint to this service. Continuing anyway."
    return 0
  fi

  c_red "✗ $name: port $port is not open — the service does not appear to be"
  c_red "  running at all. Check $LOG_DIR/$name.log for a startup error."
  return 1
}

ensure_docker_daemon() {
  if docker info >/dev/null 2>&1; then
    c_green "✓ Docker daemon is running"
    return 0
  fi

  c_yellow "Docker daemon not reachable — attempting to start Docker Desktop..."
  open -a Docker >/dev/null 2>&1 || {
    c_red "✗ Could not launch Docker Desktop automatically (open -a Docker failed)."
    c_red "  Start it manually from /Applications/Docker.app, then re-run this script."
    return 1
  }

  local tries=60 i
  echo -n "Waiting for Docker daemon to come up (up to 2 min)"
  for ((i = 1; i <= tries; i++)); do
    if docker info >/dev/null 2>&1; then
      echo ""
      c_green "✓ Docker daemon is now running"
      return 0
    fi
    echo -n "."
    sleep 2
  done

  echo ""
  c_red "✗ Docker daemon still not reachable after ~2 minutes."
  c_red "  Open Docker Desktop manually, wait for the whale icon to stop animating"
  c_red "  in the menu bar, verify with 'docker info', then re-run this script."
  return 1
}

strip_obsolete_compose_version() {
  # Docker Compose v2 no longer uses the top-level `version:` key and warns
  # on every run if it's present. Cosmetic only — safe to remove.
  local compose_file="$ROOT_DIR/docker-compose.yml"
  [[ -f "$compose_file" ]] || return 0
  if grep -qE '^version:' "$compose_file"; then
    c_yellow "Removing obsolete 'version:' key from docker-compose.yml (cosmetic, avoids a warning)"
    sed -i '' '/^version:/d' "$compose_file"
  fi
}

start_service() {
  local dir="$1" name="$2" extra_env="${3:-}"
  echo "Starting $name..."
  (
    cd "$ROOT_DIR/$dir"
    if [[ -n "$extra_env" ]]; then
      env "$extra_env" npm run start:dev
    else
      npm run start:dev
    fi
  ) > "$LOG_DIR/$name.log" 2>&1 &
  local pid=$!
  echo "$name:$pid" >> "$PID_FILE"
  echo "  → pid $pid — logs: $LOG_DIR/$name.log"
}

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
echo "== Checking prerequisites =="
all_ok=true
require_cmd node    "install from https://nodejs.org (>= 20 LTS)"      || all_ok=false
require_cmd npm     "comes with Node.js"                                || all_ok=false
require_cmd cargo   "install via https://rustup.rs"                     || all_ok=false
require_cmd flutter "install from https://flutter.dev"                  || all_ok=false
require_cmd docker  "install Docker Desktop from https://docker.com"    || all_ok=false

if docker compose version >/dev/null 2>&1; then
  c_green "✓ docker compose plugin found"
else
  c_red "✗ 'docker compose' plugin not found"
  all_ok=false
fi

if command -v rustup >/dev/null 2>&1; then
  c_green "✓ rustup found ($(rustup --version 2>&1 | head -n1))"
else
  c_yellow "⚠ rustup not found (cargo alone was detected above)."
  c_yellow "  This is only needed for the Wasm/web crypto-core build — native"
  c_yellow "  iOS/Android builds are unaffected. If you installed Rust via Homebrew"
  c_yellow "  or another non-rustup method, install rustup alongside it:"
  c_yellow "    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  c_yellow "  (does not remove your existing toolchain). This won't block startup —"
  c_yellow "  the wasm build step will just be skipped until it's available."
fi

if [[ "$all_ok" == false ]]; then
  c_red "Missing prerequisites — install the above, then re-run this script."
  exit 1
fi

if [[ "$CHECK_ONLY" == true ]]; then
  c_green "All prerequisites satisfied. (--check, exiting without starting anything)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Environment variables
# ---------------------------------------------------------------------------
if [[ ! -f "$ROOT_DIR/.env" ]]; then
  if [[ -f "$ROOT_DIR/.env.example" ]]; then
    cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
    c_yellow "Created .env from .env.example."
    c_yellow "Fill in DATABASE_URL, REDIS_URL, JWT_SECRET (>= 64 chars), AUTH_PORT,"
    c_yellow "SYNC_PORT, and SECURITY_ANALYSIS_PORT, then re-run this script."
    exit 1
  else
    c_red ".env.example not found in $ROOT_DIR — cannot continue."
    exit 1
  fi
fi
set -a
source "$ROOT_DIR/.env"
set +a
c_green "✓ .env loaded"

# ---------------------------------------------------------------------------
# 3. Dependency install
# ---------------------------------------------------------------------------
if [[ "$SKIP_INSTALL" == false ]]; then
  echo "== Installing dependencies =="
  for svc in auth-service sync-api security-analysis-service sharing-service; do
    if [[ ! -d "$ROOT_DIR/backend/$svc/node_modules" ]]; then
      echo "Installing backend/$svc ..."
      (cd "$ROOT_DIR/backend/$svc" && npm install)
    else
      echo "backend/$svc: node_modules already present, skipping install"
    fi
  done

  echo "Installing Flutter app dependencies..."
  (cd "$ROOT_DIR/app" && flutter pub get)

  if [[ -d "$ROOT_DIR/browser-extension" ]]; then
    echo "Installing browser-extension dependencies..."
    (cd "$ROOT_DIR/browser-extension" && flutter pub get)
  fi
else
  c_yellow "Skipping dependency install (--skip-install)"
fi

# ---------------------------------------------------------------------------
# 4. Docker infrastructure
# ---------------------------------------------------------------------------
if [[ "$SKIP_DOCKER" == false ]]; then
  echo "== Starting PostgreSQL + Redis =="
  ensure_docker_daemon || exit 1
  strip_obsolete_compose_version
  (cd "$ROOT_DIR" && docker compose up -d)
  sleep 2
  (cd "$ROOT_DIR" && docker compose ps)
else
  c_yellow "Skipping Docker infra (--skip-docker) — ensure Postgres/Redis are reachable"
fi

# ---------------------------------------------------------------------------
# 5. Native crypto core (Rust)
# ---------------------------------------------------------------------------
if [[ "$SKIP_RUST" == false ]]; then
  echo "== Building native crypto core (Rust) =="
  (cd "$ROOT_DIR/native/crypto_core" && cargo build)

  echo "Running crypto core tests (mandatory before any crypto change)..."
  (cd "$ROOT_DIR/native/crypto_core" && cargo test)

  if command -v rustup >/dev/null 2>&1; then
    if ! rustup target list --installed | grep -q '^wasm32-unknown-unknown$'; then
      echo "Adding wasm32-unknown-unknown target..."
      rustup target add wasm32-unknown-unknown
    fi
    echo "Building wasm32 target (required for the web build)..."
    (cd "$ROOT_DIR/native/crypto_core" && cargo build --target wasm32-unknown-unknown --features wasm)
  else
    c_yellow "⚠ rustup not found — skipping the Wasm build for the web crypto core."
    c_yellow "  Native builds (iOS/Android/macOS) are unaffected. To enable the web"
    c_yellow "  build, install rustup (see the prerequisites check above) and re-run"
    c_yellow "  this script, or manually run:"
    c_yellow "    rustup target add wasm32-unknown-unknown"
    c_yellow "    cd native/crypto_core && cargo build --target wasm32-unknown-unknown --features wasm"
  fi
else
  c_yellow "Skipping Rust build (--skip-rust)"
fi

# ---------------------------------------------------------------------------
# 6. Backend services (background, logged, PID-tracked)
# ---------------------------------------------------------------------------
echo "== Starting backend services =="
start_service "backend/auth-service"               "auth-service"
start_service "backend/sync-api"                    "sync-api"
start_service "backend/security-analysis-service"   "security-analysis-service"
start_service "backend/sharing-service"             "sharing-service" "SHARING_PORT=3004"

echo "== Waiting for health checks =="
wait_for_health "http://localhost:${AUTH_PORT:-3001}/health"              "auth-service"               "${AUTH_PORT:-3001}"
wait_for_health "http://localhost:${SYNC_PORT:-3002}/health"              "sync-api"                    "${SYNC_PORT:-3002}"
wait_for_health "http://localhost:${SECURITY_ANALYSIS_PORT:-3003}/health" "security-analysis-service"   "${SECURITY_ANALYSIS_PORT:-3003}"
wait_for_health "http://localhost:3004/health"                            "sharing-service"             "3004"

c_green "All backend services are up."
echo "Logs: $LOG_DIR/"
echo "PIDs: $PID_FILE — stop everything anytime with ./stop-sentinelvault.sh"

if [[ "$BACKEND_ONLY" == true ]]; then
  c_green "Backend-only mode (--backend-only) — Flutter app not started."
  exit 0
fi

# ---------------------------------------------------------------------------
# 7. Flutter app
# ---------------------------------------------------------------------------
echo "== Launching Flutter app =="
cd "$ROOT_DIR/app"

if [[ -z "$DEVICE" ]]; then
  echo "Available devices:"
  flutter devices
  echo ""
  echo "Choose a target to run:"
  select choice in "iOS Simulator" "Android Emulator" "Chrome (Web)" "macOS Desktop" "Skip — leave backend running only"; do
    case "$choice" in
      "iOS Simulator")                     DEVICE="iPhone 16"; break ;;
      "Android Emulator")                  DEVICE="emulator-5554"; break ;;
      "Chrome (Web)")                       DEVICE="chrome"; break ;;
      "macOS Desktop")                      DEVICE="macos"; break ;;
      "Skip — leave backend running only") DEVICE=""; break ;;
      *) echo "Invalid choice, try again." ;;
    esac
  done
fi

if [[ -n "$DEVICE" ]]; then
  c_yellow "Reminder: successful account login does NOT unlock the vault —"
  c_yellow "the Master Password unlock step is always required separately."
  flutter run -d "$DEVICE"
else
  c_green "Backend services remain running in the background."
  echo "Run Flutter yourself later with: cd app && flutter run -d <device>"
fi