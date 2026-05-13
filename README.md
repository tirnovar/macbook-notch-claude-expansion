# Claude Notch

<img width="100" height="100" alt="clawd-notch-peek" src="https://github.com/user-attachments/assets/0f4cd58e-dcfe-4c3b-baf5-129bc10cf7c3" />

A native macOS app that turns the MacBook hardware notch into a live Claude Code session monitor and permission approval UI. No Dock icon. No window switching. Just the notch.

## What it does

### Status bar

Whenever a Claude Code session is running, the notch silently expands horizontally, showing a session count and a status dot:

| Dot colour | Meaning |
|---|---|
| Amber (pulsing) | At least one session is actively working or waiting for permission |
| Gray (static) | All sessions are idle |

Click the chevron to open the detail panel — each session row has its own dot, an entrypoint icon, and is clickable (focuses the terminal, editor, or Claude Desktop that owns the session).

| Dot colour | Session state |
|---|---|
| Amber | Active (tool running) or waiting for permission |
| Gray | Idle — no activity for > 30 s |
| Green | Finished |

### Permission card

When Claude Code requests permission for a tool call, the notch expands vertically into a card showing the tool name, what it will do, and four buttons:

| Button | Effect |
|---|---|
| **Accept Once** | Allows this one request, no cache |
| **For Session** | Allows the same tool pattern for the rest of this session |
| **Permanently** | Writes the pattern to `~/.claude/settings.json` (global allow) |
| **Decline** | Blocks the tool call |

No response after 90 seconds → automatic allow (Claude Code never gets stuck).

## Installation

### Download the latest release

1. Go to the [Releases](../../releases) page and download `ClaudeNotchExpansion.app.zip`
2. Unzip and move `ClaudeNotchExpansion.app` to `/Applications/`
3. Launch the app

On first launch the app automatically:
- Registers itself as a `PreToolUse` hook in `~/.claude/settings.json`
- Installs a LaunchAgent at `~/Library/LaunchAgents/cz.databrothers.claude-notch-expansion.plist` (`KeepAlive=true`) so it starts at login and restarts after crashes
- Shows a one-time confirmation alert

On every subsequent launch the hook path and LaunchAgent are silently updated if the `.app` bundle was moved.

### Build from source

**Requirements:** macOS 14.0+, Swift 5.10+, Python 3

```bash
git clone <repo>
cd macbook-notch-claude-expansion
make app
cp -r .build/ClaudeNotchExpansion.app /Applications/
open /Applications/ClaudeNotchExpansion.app
```

## Testing without a live Claude Code session

```bash
# Simulate a permission request (app must be running first)
make test-hook

# Create a fake session file so the status bar appears; Ctrl+C removes it
make test-session
```

## How the hook works

`claude-notch-hook.py` is a synchronous Claude Code `PreToolUse` hook. Claude Code calls it before every tool use, passes data on stdin, and waits for a JSON response on stdout.

Request order:
1. If the `.app` bundle no longer exists → removes its own hook entry from `settings.json` and exits (self-cleanup on app deletion)
2. Checks `permissions.allow` across all settings layers (global `~/.claude/settings.json`, project `.claude/settings.json`, `.claude/settings.local.json`) — fast exit if already allowed
3. Checks the session cache (`/tmp/claude-notch-session-{id}.json`) — fast exit if already approved for this session
4. Connects to the Unix socket. If the app is not running, launches it via `open -g` and polls (up to 3 s), then retries. If unreachable → falls back to Claude Code's built-in UI
5. Sends the request and blocks waiting for the UI response (up to 90 s)
6. Timeout → allow (Claude Code never gets stuck)

## Architecture

```
~/.claude/sessions/{pid}.json  ──FSEvents──►  SessionMonitor (actor)
                                                    │
~/.claude/settings.json ─auto hook install─►  HookInstaller
                                                    │
PreToolUse hook (Python) ──Unix socket──►  PermissionServer (actor)
                                                    │
                                          AppState (@MainActor)
                                                    │
                                       NotchWindowController (NSWindow)
                                                    │
                                            SwiftUI Views
```

**IPC protocol:** Unix domain socket `/tmp/claude-notch-monitor.sock`, 4-byte big-endian length-prefixed JSON frames. One request per connection, hook blocks until the app responds.

**Session detection:** FSEvents watches `~/.claude/sessions/`. Each running Claude Code process writes `{pid}.json`. App validates liveness via `kill(pid, 0)`, rechecked every 30 s.

**Three-level permission cache:**
- *Accept Once* — no cache
- *For Session* — in-process dict + `/tmp/claude-notch-session-{id}.json`
- *Permanently* — atomic write to `~/.claude/settings.json` → `permissions.allow`

## Requirements

- macOS 14.0 (Sonoma) or later — MacBook with hardware notch
- Swift 5.10+ (build from source only)
- Python 3 (ships with macOS, used for the hook script)

## Bundle identifier

`cz.databrothers.claude-notch-expansion`
