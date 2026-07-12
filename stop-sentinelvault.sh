#!/usr/bin/env bash
#
# SentinelVault — Local Dev Stop Script (macOS)
#
# Stops the background backend service processes started by
# start-sentinelvault.sh, and optionally stops the Docker infrastructure
# (Postgres + Redis) too.
#
# Usage:
#   ./stop-sentinelvault.sh            Stop backend services, then ask
#                                       whether to also stop Docker infra
#   ./stop-sentinelvault.sh --docker   Also stop Docker infra, no prompt
#   ./stop-sentinelvault.sh --logs     Print each service's last 20 log
#                                       lines before stopping (useful if
#                                       something crashed)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$ROOT_DIR/.sentinelvault"
LOG_DIR="$STATE_DIR/logs"
PID_FILE="$STATE_DIR/pids"

STOP_DOCKER=false
SHOW_LOGS=false
for arg in "$@"; do
  case "$arg" in
    --docker) STOP_DOCKER=true ;;
    --logs) SHOW_LOGS=true ;;
  esac
done

c_green()  { printf "\033[0;32m%s\033[0m\n" "$1"; }
c_yellow() { printf "\033[0;33m%s\033[0m\n" "$1"; }

if [[ "$SHOW_LOGS" == true && -d "$LOG_DIR" ]]; then
  for f in "$LOG_DIR"/*.log; do
    [[ -f "$f" ]] || continue
    echo "---- $(basename "$f") (last 20 lines) ----"
    tail -n 20 "$f"
    echo ""
  done
fi

if [[ -f "$PID_FILE" ]]; then
  while IFS=: read -r name pid; do
    [[ -z "${pid:-}" ]] && continue
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null && c_green "Stopped $name (pid $pid)"
    else
      c_yellow "$name (pid $pid) was already stopped"
    fi
  done < "$PID_FILE"
  : > "$PID_FILE"
else
  c_yellow "No PID file found at $PID_FILE — nothing to stop."
fi

if [[ "$STOP_DOCKER" == true ]]; then
  (cd "$ROOT_DIR" && docker compose stop)
  c_green "Docker infrastructure stopped (data preserved)."
else
  read -r -p "Also stop Docker infrastructure (Postgres/Redis)? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    (cd "$ROOT_DIR" && docker compose stop)
    c_green "Docker infrastructure stopped (data preserved)."
  else
    c_yellow "Docker infrastructure left running."
  fi
fi
