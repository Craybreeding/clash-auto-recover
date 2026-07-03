#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
STATE_DIR="${CLASH_RECOVER_STATE_DIR:-$HOME/.local/state/clash-recover}"
LOG_DIR="${CLASH_RECOVER_LOG_DIR:-$HOME/Library/Logs/clash-recover}"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LABEL_PREFIX="${CLASH_RECOVER_LABEL_PREFIX:-io.github.craybreeding}"
HEALTH_LABEL="$LABEL_PREFIX.clash-auto-recover"
DAILY_LABEL="$LABEL_PREFIX.clash-daily-refresh"
INSTALL_DAILY=0
DRY_RUN=0
NO_LOAD=0
DAILY_HOUR=8
DAILY_MINUTE=30
FALLBACK_PROXY=""
APP_NAME="${CLASH_APP_NAME:-Clash Verge}"
SOCKET="${CLASH_SOCKET:-/tmp/verge/verge-mihomo.sock}"

usage() {
  cat <<'EOF'
usage: ./install.sh [options]

Options:
  --daily-refresh             Install the daily remote-profile refresh agent.
  --daily-time HH:MM          Daily refresh time, default 08:30.
  --fallback-proxy URL        Optional fallback HTTP proxy, for example http://192.0.2.10:7897.
  --prefix DIR                Install prefix, default ~/.local.
  --label-prefix PREFIX       LaunchAgent label prefix, default io.github.craybreeding.
  --app-name NAME             macOS app name, default "Clash Verge".
  --socket PATH               Mihomo controller unix socket, default /tmp/verge/verge-mihomo.sock.
  --dry-run                   Print planned actions without writing files or loading launchd agents.
  --no-load                   Write files and validate plists, but do not load launchd agents.
  -h, --help                  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --daily-refresh)
      INSTALL_DAILY=1
      shift
      ;;
    --daily-time)
      [[ $# -ge 2 ]] || { echo "--daily-time requires HH:MM" >&2; exit 64; }
      if [[ ! "$2" =~ ^([0-9]|[01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        echo "--daily-time must be HH:MM in 24-hour time" >&2
        exit 64
      fi
      DAILY_HOUR="${2%%:*}"
      DAILY_MINUTE="${2##*:}"
      DAILY_HOUR="$((10#$DAILY_HOUR))"
      DAILY_MINUTE="$((10#$DAILY_MINUTE))"
      shift 2
      ;;
    --fallback-proxy)
      [[ $# -ge 2 ]] || { echo "--fallback-proxy requires URL" >&2; exit 64; }
      FALLBACK_PROXY="$2"
      shift 2
      ;;
    --prefix)
      [[ $# -ge 2 ]] || { echo "--prefix requires DIR" >&2; exit 64; }
      PREFIX="$2"
      BIN_DIR="$PREFIX/bin"
      shift 2
      ;;
    --label-prefix)
      [[ $# -ge 2 ]] || { echo "--label-prefix requires PREFIX" >&2; exit 64; }
      LABEL_PREFIX="$2"
      HEALTH_LABEL="$LABEL_PREFIX.clash-auto-recover"
      DAILY_LABEL="$LABEL_PREFIX.clash-daily-refresh"
      shift 2
      ;;
    --app-name)
      [[ $# -ge 2 ]] || { echo "--app-name requires NAME" >&2; exit 64; }
      APP_NAME="$2"
      shift 2
      ;;
    --socket)
      [[ $# -ge 2 ]] || { echo "--socket requires PATH" >&2; exit 64; }
      SOCKET="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-load)
      NO_LOAD=1
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_BIN="$SCRIPT_DIR/bin/clash-auto-recover"
TARGET_BIN="$BIN_DIR/clash-auto-recover"
HEALTH_PLIST="$LAUNCH_AGENT_DIR/$HEALTH_LABEL.plist"
DAILY_PLIST="$LAUNCH_AGENT_DIR/$DAILY_LABEL.plist"
UID_VALUE="$(id -u)"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 69
  }
}

validate_proxy_url() {
  [[ -z "$FALLBACK_PROXY" ]] && return 0
  ruby -ruri -e '
    uri = URI(ARGV.fetch(0))
    abort "fallback proxy must be http:// or https://" unless %w[http https].include?(uri.scheme)
    abort "authenticated fallback proxy URLs are not supported" if uri.user || uri.password
    abort "fallback proxy must include host and port" if uri.host.to_s.empty? || uri.port.nil?
  ' "$FALLBACK_PROXY"
}

write_health_plist() {
  local path="$1"
  cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$HEALTH_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$TARGET_BIN</string>
    <string>health</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLASH_APP_NAME</key>
    <string>$APP_NAME</string>
    <key>CLASH_SOCKET</key>
    <string>$SOCKET</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>60</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/launchd.err.log</string>
</dict>
</plist>
EOF
}

write_daily_plist() {
  local path="$1"
  cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$DAILY_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$TARGET_BIN</string>
    <string>daily-refresh-if-needed</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLASH_APP_NAME</key>
    <string>$APP_NAME</string>
    <key>CLASH_SOCKET</key>
    <string>$SOCKET</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>$DAILY_HOUR</integer>
    <key>Minute</key>
    <integer>$DAILY_MINUTE</integer>
  </dict>
  <key>StartInterval</key>
  <integer>1800</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/daily-refresh.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/daily-refresh.err.log</string>
</dict>
</plist>
EOF
}

load_agent() {
  local label="$1"
  local plist="$2"
  launchctl bootout "gui/$UID_VALUE" "$plist" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID_VALUE" "$plist"
  launchctl enable "gui/$UID_VALUE/$label" >/dev/null 2>&1 || true
  launchctl kickstart -k "gui/$UID_VALUE/$label" >/dev/null 2>&1 || true
}

require_cmd bash
require_cmd curl
require_cmd jq
require_cmd ruby
require_cmd plutil
require_cmd launchctl
require_cmd networksetup
require_cmd scutil
validate_proxy_url

if [[ "$DRY_RUN" == "1" ]]; then
  echo "install binary: $SOURCE_BIN -> $TARGET_BIN"
  echo "health agent: $HEALTH_PLIST label=$HEALTH_LABEL"
  if [[ "$INSTALL_DAILY" == "1" ]]; then
    echo "daily agent: $DAILY_PLIST label=$DAILY_LABEL time=$(printf '%02d:%02d' "$DAILY_HOUR" "$DAILY_MINUTE")"
  fi
  if [[ -n "$FALLBACK_PROXY" ]]; then
    echo "fallback proxy will be stored in $STATE_DIR/fallback-proxy"
  fi
  exit 0
fi

mkdir -p "$BIN_DIR" "$STATE_DIR" "$LOG_DIR" "$LAUNCH_AGENT_DIR"
install -m 0755 "$SOURCE_BIN" "$TARGET_BIN"

if [[ -n "$FALLBACK_PROXY" ]]; then
  printf '%s\n' "$FALLBACK_PROXY" > "$STATE_DIR/fallback-proxy"
  chmod 0600 "$STATE_DIR/fallback-proxy"
fi

write_health_plist "$HEALTH_PLIST"
plutil -lint "$HEALTH_PLIST" >/dev/null
if [[ "$NO_LOAD" == "0" ]]; then
  load_agent "$HEALTH_LABEL" "$HEALTH_PLIST"
fi

if [[ "$INSTALL_DAILY" == "1" ]]; then
  write_daily_plist "$DAILY_PLIST"
  plutil -lint "$DAILY_PLIST" >/dev/null
  if [[ "$NO_LOAD" == "0" ]]; then
    load_agent "$DAILY_LABEL" "$DAILY_PLIST"
  fi
fi

echo "installed $TARGET_BIN"
echo "health agent: $HEALTH_LABEL"
if [[ "$INSTALL_DAILY" == "1" ]]; then
  echo "daily agent: $DAILY_LABEL"
fi
if [[ "$NO_LOAD" == "1" ]]; then
  echo "launchd load skipped (--no-load)"
fi
echo "check status: $TARGET_BIN status"
