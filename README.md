# clash-auto-recover

macOS LaunchAgent helper for keeping Clash Verge / Mihomo usable after proxy, TUN, controller, or subscription refresh failures.

It was built for machines that depend on `127.0.0.1:7897` for developer tools. The recovery loop checks real outbound access, refreshes proxy providers, selects a healthy `GLOBAL` candidate, restores macOS system proxy settings, and can optionally refresh the active remote Clash Verge profile once per day.

## Requirements

- macOS
- Clash Verge or Clash Verge Rev
- `jq` available in `PATH`
- Clash/Mihomo controller unix socket at `/tmp/verge/verge-mihomo.sock` by default
- A mixed/http proxy port discoverable from Mihomo config, macOS system proxy, or default `7897`

Install `jq` with Homebrew if needed:

```bash
brew install jq
```

## Install

Clone the repository, then install the health agent:

```bash
git clone https://github.com/Craybreeding/clash-auto-recover.git
cd clash-auto-recover
./install.sh
```

Install health checks plus daily subscription refresh:

```bash
./install.sh --daily-refresh --daily-time 08:30
```

Optional fallback proxy:

```bash
./install.sh --daily-refresh --fallback-proxy http://192.0.2.10:7897
```

The fallback proxy URL is written only to your local state file:

```text
~/.local/state/clash-recover/fallback-proxy
```

It is not committed to the repository. Authenticated proxy URLs are intentionally rejected to avoid credential leakage and ambiguous macOS proxy behavior.

## Commands

```bash
~/.local/bin/clash-auto-recover status
~/.local/bin/clash-auto-recover health
~/.local/bin/clash-auto-recover recover
~/.local/bin/clash-auto-recover daily-refresh-if-needed
```

Logs:

```text
~/Library/Logs/clash-recover/recover.log
~/Library/Logs/clash-recover/launchd.out.log
~/Library/Logs/clash-recover/daily-refresh.out.log
```

LaunchAgent labels:

```text
io.github.craybreeding.clash-auto-recover
io.github.craybreeding.clash-daily-refresh
```

## How Recovery Works

The health agent runs every 60 seconds. After repeated failures it:

1. Opens Clash Verge if the controller is unavailable.
2. Falls back to starting `verge-mihomo` directly if the app does not expose the controller.
3. Turns off macOS system proxy and TUN to avoid a dead proxy path.
4. Updates Clash proxy providers and runs group delay checks.
5. Tests `GLOBAL` candidates against Google 204, GitHub, OpenAI, and Gemini endpoints.
6. Re-enables the local system proxy and the previous TUN preference when a candidate is healthy.
7. Uses the optional fallback proxy only when local recovery still fails.

The daily refresh agent downloads the active remote Clash Verge profile, validates that it looks like a proxy YAML file, restarts Clash Verge, and then runs recovery. It records a daily success marker to prevent repeated refreshes on the same day.

## Configuration

You can override these environment variables in your shell or in a custom LaunchAgent:

| Variable | Default |
| --- | --- |
| `CLASH_APP_NAME` | `Clash Verge` |
| `CLASH_SOCKET` | `/tmp/verge/verge-mihomo.sock` |
| `CLASH_RECOVER_HEALTH_ROUNDS` | `2` |
| `CLASH_RECOVER_MIN_OK` | `4 * rounds` |
| `CLASH_RECOVER_FAIL_THRESHOLD` | `2` |
| `CLASH_RECOVER_MIN_INTERVAL` | `180` |
| `CLASH_RECOVER_MAX_CANDIDATES` | `64` |
| `CLASH_RECOVER_REENABLE_SYSTEM_PROXY` | `1` |
| `CLASH_RECOVER_REENABLE_TUN` | `preserve` |
| `CLASH_FALLBACK_PROXY` | empty, or state file value |

For Clash Verge Rev with a different app name:

```bash
./install.sh --app-name "Clash Verge Rev"
```

## Dry Run

```bash
./install.sh --daily-refresh --dry-run
./install.sh --daily-refresh --no-load
./uninstall.sh --dry-run
```

## Uninstall

```bash
./uninstall.sh
```

Remove logs and state too:

```bash
./uninstall.sh --remove-state
```

## Safety Notes

- The tool changes user-level macOS network proxy settings through `networksetup`.
- It does not require root and does not edit system daemons, DNS, nginx, cloudflared, or application data.
- Logs include proxy host and port, but not subscription URLs or proxy credentials.
- The active Clash Verge remote profile URL is read from your local `profiles.yaml` only to download the same profile again; the URL is not printed.
