![Claude Notch hero](assets/clawd-notch-banner.svg)

# Claude Notch

**Claude Code session monitor and permission UI — living in the only screen real estate your MacBook was wasting.**

The hardware notch exists. It's always visible. Claude Notch puts it to work: live session status, permission approvals, and API usage — all without switching windows or touching the terminal.

---

## Why it exists

You're deep in your editor. Claude Code is running somewhere in the background — maybe working, maybe blocked waiting for you to approve a tool call, maybe already done. You have no idea without switching focus.

Claude Notch solves this with zero context switches. The notch shows you what's happening. You approve or deny from there. You never leave your editor.

---

## What you get

### Always-visible session status

A small indicator lives in the notch bar. It tells you the state of every Claude Code session at a glance — no terminal, no Dock, no window management.

![Notch bar — 3 sessions, mixed states](assets/notch-closed-with-active-sessions.png)

#### What the colors mean

The indicator color reflects the worst-case state across all your sessions:

| Color | State |
|---|---|
| **Amber** (pulsing) | At least one session is actively working or waiting for your approval |
| **Green** (static) | All sessions finished — Claude is done |
| **Gray** (static) | All sessions idle — no active work |

When sessions are in **mixed states** — some working, some done — the pill shows both colors simultaneously (amber + green), so you know at a glance that not everything has finished yet.

**One session** shows a dot. **Two or more sessions** spring-animate the dot into a pill with a session count. Drop back to one, it morphs back. Click anywhere on the bar to open the detail panel:

![Detail panel — sessions and usage](assets/notch-opened-with-active-sessions.png)

Each row shows the project name, working directory, entrypoint type, elapsed time, and status. Click a row to focus the right terminal or editor window.

---

### Permission approvals without leaving your editor

When Claude Code needs to run a tool — write a file, execute a shell command, call an API — it asks first. Normally, that means hunting for the right terminal tab. With Claude Notch, the notch expands downward into a permission card.

![Permission card](assets/notch-permission-request.png)

Four choices, always visible:

| Action | What it does |
|---|---|
| **Accept Once** | Approves this specific call, nothing else |
| **For Session** | Approves the same tool pattern for the rest of this session |
| **Permanently** | Writes the pattern to `~/.claude/settings.json` — never asked again |
| **Decline** | Blocks the call |

Walk away? After 90 seconds with no response, the call is automatically approved. Claude Code never gets stuck waiting on you.

---

### API usage at a glance

The bottom of the detail panel shows your Claude API utilization in real time — 5-hour and 7-day windows, each with a reset countdown. The ring indicator in the notch bar mirrors the 5h utilization at all times.

Know before you hit a rate limit, not after.

---

## Installation

### Download (recommended)

1. Go to [**Releases**](../../releases) and download `ClaudeNotchExpansion.app.zip`
2. Unzip → move `ClaudeNotchExpansion.app` to `/Applications/`
3. Launch the app

On first launch, Claude Notch automatically:
- Registers a `PreToolUse` hook in `~/.claude/settings.json`
- Installs a LaunchAgent so it starts at login and self-restarts after crashes

If you move the `.app` later, both the hook and LaunchAgent paths update automatically on next launch.

### Build from source

**Requirements:** macOS 14.0+, Swift 5.10+, Python 3

```bash
git clone <repo>
cd macbook-notch-claude-expansion
make app
cp -r .build/ClaudeNotchExpansion.app /Applications/
open /Applications/ClaudeNotchExpansion.app
```

---

## Requirements

- macOS 14.0 (Sonoma) or later
- MacBook with hardware notch (MacBook Pro 2021+, MacBook Air M2+)
- Python 3 (ships with macOS — used by the hook script)
- Swift 5.10+ (build from source only)

---

## Testing without a live Claude Code session

```bash
# Simulate a permission request (app must be running)
make test-hook

# Fake a session file so the status bar appears; Ctrl+C removes it
make test-session
```

---

## How it works under the hood

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

**IPC:** Unix domain socket at `/tmp/claude-notch-monitor.sock`, 4-byte big-endian length-prefixed JSON. One request per connection; the hook blocks until the app responds or times out.

**Session detection:** FSEvents watches `~/.claude/sessions/`. Each Claude Code process writes `{pid}.json`. Liveness is validated via `kill(pid, 0)`, rechecked every 30 s.

**Permission cache (three levels):**
- *Accept Once* — no cache, single approval
- *For Session* — in-process dict + `/tmp/claude-notch-session-{id}.json` (hook reads it on restart)
- *Permanently* — atomic write to `~/.claude/settings.json → permissions.allow`

---

## Bundle identifier

`cz.databrothers.claude-notch-expansion`
