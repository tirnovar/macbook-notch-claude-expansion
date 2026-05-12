# MacBook Notch — Claude Code Monitor

A native macOS app that turns the MacBook notch into a live Claude Code session monitor and permission approval UI. No Dock icon. No switching to the terminal. Just the notch.

## What it does

**When Claude Code is running** the notch silently expands horizontally, showing a status bar with colour-coded session dots:

| Colour | Meaning |
|--------|---------|
| Purple | Session active (tool running) |
| Amber  | Waiting for your permission |
| Green  | Session finished (auto-hides in 5 s) |

**When Claude Code asks for a tool permission** the notch expands vertically into a card showing the tool name, what it will do, and four buttons:

| Button | Effect |
|--------|--------|
| Accept Once | Allows this one request, no cache |
| Accept for Session | Allows same tool pattern for the rest of this session |
| Accept Permanently | Writes the tool key to `~/.claude/settings.json` |
| Decline | Blocks the tool call |

Unanswered after 90 seconds → automatic allow (Claude Code never gets stuck).

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

**IPC protocol:** Unix domain socket at `/tmp/claude-notch-monitor.sock` with 4-byte big-endian length-prefixed JSON frames. One request per connection, hook blocks until the app responds.

**Session detection:** FSEvents watches `~/.claude/sessions/`. Each running Claude Code process writes a `{pid}.json` there. The app validates process liveness via `kill(pid, 0)`.

**Three-level permission cache:**
- *Accept Once* — no cache, request handled and forgotten
- *For Session* — in-process dict + `/tmp/claude-notch-session-{id}.json` (hook reads this before connecting to the socket, avoiding a full UI roundtrip)
- *Permanently* — atomic write to `~/.claude/settings.json` `permissions.allow`

## Requirements

- macOS 14.0 (Sonoma) or later — MacBook with hardware notch
- Swift 5.10+ (`swift --version`)
- Python 3 (ships with macOS, used for the hook script)

## Build & run

```bash
# Build release binary + assemble .app bundle
make app

# Build and immediately open
make run

# Run in foreground (stdout visible — useful for debugging)
make run-fg

# Clean build artefacts
make clean
```

## First launch

On first launch the app automatically:

1. Copies `claude-notch-hook.py` to `~/.claude/` and registers it as a `PreToolUse` hook in `~/.claude/settings.json`
2. Installs a LaunchAgent at `~/Library/LaunchAgents/cz.databrothers.claude-notch-expansion.plist` so it starts at login
3. Shows a one-time `NSAlert` confirming the hook was installed

After that, every Claude Code session that triggers a tool call will route through the notch UI.

## Testing without a live Claude Code session

```bash
# Simulate a permission request (app must be running first)
make test-hook

# Create a fake session file so the status bar appears
make test-session   # press Ctrl+C to remove the fake session
```

## Project structure

```
Sources/ClaudeNotchExpansion/
├── main.swift                        NSApplication entry, AppDelegate
├── State/
│   ├── AppState.swift                @MainActor ObservableObject, state machine
│   ├── ClaudeSession.swift           Session model + SessionState enum
│   └── PendingPermission.swift       Permission model + AnyCodable helper
├── Services/
│   ├── SessionMonitor.swift          FSEvents watcher, idle/finished tracking
│   ├── PermissionServer.swift        Unix socket server, continuation-based blocking
│   ├── SessionPermissionCache.swift  In-process + /tmp disk cache
│   ├── PermanentCacheManager.swift   Atomic write to ~/.claude/settings.json
│   └── HookInstaller.swift           Hook + LaunchAgent auto-install
├── Window/
│   └── NotchWindowController.swift   Borderless NSWindow above menu bar
├── Views/
│   ├── NotchContentView.swift        Root SwiftUI view, state switcher
│   ├── SessionBarView.swift          Horizontal status bar
│   └── PermissionCardView.swift      Vertical permission card
└── Resources/
    ├── Info.plist                    LSUIElement=YES, bundle metadata
    └── claude-notch-hook.py          Bundled PreToolUse hook script
```

## How the hook works

`claude-notch-hook.py` is a synchronous Claude Code `PreToolUse` hook. Claude Code calls it before every tool use, passing tool data on stdin and expecting a JSON response on stdout:

- `exit 0` + `"permissionDecision": "allow"` → tool proceeds
- `exit 2` + `"permissionDecision": "deny"` → tool is blocked

The script:
1. Checks the session-level `/tmp` cache — if already approved, exits immediately without touching the socket
2. Connects to the Unix socket (2 s timeout — if the app isn't running, exits 0 and allows)
3. Sends the request and blocks waiting for the UI response (up to 90 s)
4. On timeout or any unexpected error, allows (so Claude Code is never stuck)

## Bundle identifier

`cz.databrothers.claude-notch-expansion`
