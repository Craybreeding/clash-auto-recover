#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
LABEL_PREFIX="${CLASH_RECOVER_LABEL_PREFIX:-io.github.craybreeding}"
HEALTH_LABEL="$LABEL_PREFIX.clash-auto-recover"
DAILY_LABEL="$LABEL_PREFIX.clash-daily-refresh"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
REMOVE_STATE=0
DRY_RUN=0

usage() {
  cat <<'EOF'
usage: ./uninstall.sh [options]

Options:
  --remove-state              Also remove ~/.local/state/clash-recover and logs.
  --prefix DIR                Install prefix, default ~/.local.
  --label-prefix PREFIX       LaunchAgent label prefix, default io.github.craybreeding.
  --dry-run                   Print planned actions without removing files.
  -h, --help                  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-state)
      REMOVE_STATE=1
      shift
      ;;
    --prefix)
      [[ $# -ge 2 ]] || { echo "--prefix requires DIR" >&2; exit 64; }
      PREFIX="$2"
      shift 2
      ;;
    --label-prefix)
      [[ $# -ge 2 ]] || { echo "--label-prefix requires PREFIX" >&2; exit 64; }
      LABEL_PREFIX="$2"
      HEALTH_LABEL="$LABEL_PREFIX.clash-auto-recover"
      DAILY_LABEL="$LABEL_PREFIX.clash-daily-refresh"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

UID_VALUE="$(id -u)"
TARGET_BIN="$PREFIX/bin/clash-auto-recover"
HEALTH_PLIST="$LAUNCH_AGENT_DIR/$HEALTH_LABEL.plist"
DAILY_PLIST="$LAUNCH_AGENT_DIR/$DAILY_LABEL.plist"
STATE_DIR="${CLASH_RECOVER_STATE_DIR:-$HOME/.local/state/clash-recover}"
LOG_DIR="${CLASH_RECOVER_LOG_DIR:-$HOME/Library/Logs/clash-recover}"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "unload labels: $HEALTH_LABEL $DAILY_LABEL"
  echo "remove files: $TARGET_BIN $HEALTH_PLIST $DAILY_PLIST"
  if [[ "$REMOVE_STATE" == "1" ]]; then
    echo "remove state/logs: $STATE_DIR $LOG_DIR"
  fi
  exit 0
fi

launchctl bootout "gui/$UID_VALUE" "$HEALTH_PLIST" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID_VALUE" "$DAILY_PLIST" >/dev/null 2>&1 || true
rm -f "$HEALTH_PLIST" "$DAILY_PLIST" "$TARGET_BIN"

if [[ "$REMOVE_STATE" == "1" ]]; then
  rm -rf "$STATE_DIR" "$LOG_DIR"
fi

echo "uninstalled clash-auto-recover"
