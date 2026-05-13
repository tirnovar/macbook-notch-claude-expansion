#!/usr/bin/env python3
"""
claude-notch-hook.py
PreToolUse hook that forwards permission requests to the macOS notch app.
Falls through (allow) if the app is not running or times out.
"""
import sys
import json
import socket
import struct
import uuid
import os
import re
import time

SOCKET_PATH = "/tmp/claude-notch-monitor.sock"
CONNECT_TIMEOUT = 2.0   # seconds to wait for the app to accept connection
RESPONSE_TIMEOUT = 90.0 # seconds to wait for user decision (allow on timeout)


# MARK: - Framing helpers

def _read_framed(sock):
    """Read a 4-byte big-endian length-prefixed JSON message."""
    header = b""
    while len(header) < 4:
        chunk = sock.recv(4 - len(header))
        if not chunk:
            raise ConnectionError("socket closed while reading header")
        header += chunk
    length = struct.unpack(">I", header)[0]
    body = b""
    while len(body) < length:
        chunk = sock.recv(length - len(body))
        if not chunk:
            raise ConnectionError("socket closed while reading body")
        body += chunk
    return json.loads(body.decode("utf-8"))


def _write_framed(sock, payload):
    """Write a 4-byte big-endian length-prefixed JSON message."""
    data = json.dumps(payload).encode("utf-8")
    sock.sendall(struct.pack(">I", len(data)) + data)


# MARK: - Tool key (must mirror Swift makeToolKey)

def _make_tool_key(tool_name, tool_input):
    if tool_name == "Bash":
        command = tool_input.get("command", "")
        parts = command.split()
        base = " ".join(parts[:2]) if len(parts) >= 2 else command
        return f"Bash({base}:*)"
    elif tool_name in ("Write", "Edit", "MultiEdit"):
        fp = tool_input.get("file_path", "")
        _, ext = os.path.splitext(fp)
        return f"{tool_name}(**/*{ext})" if ext else f"{tool_name}({fp})"
    elif tool_name == "Read":
        fp = tool_input.get("file_path", "")
        return f"Read({fp})"
    return tool_name


# MARK: - Global permissions.allow check

def _glob_to_regex(pattern):
    """Convert a glob pattern (supporting ** and *) to a compiled regex."""
    parts = pattern.split('**')
    regex_parts = []
    for part in parts:
        sub = part.split('*')
        regex_parts.append('[^/]*'.join(re.escape(s) for s in sub))
    return re.compile(''.join(['.*'.join(regex_parts)]) + '$')


def _is_allowed_by_settings(tool_name, tool_input):
    """Return True if this tool call matches any entry in ~/.claude/settings.json permissions.allow."""
    settings_path = os.path.expanduser("~/.claude/settings.json")
    try:
        with open(settings_path) as f:
            settings = json.load(f)
        allow_patterns = settings.get("permissions", {}).get("allow", [])
    except Exception:
        return False

    tool_key = _make_tool_key(tool_name, tool_input)
    for pattern in allow_patterns:
        try:
            if _glob_to_regex(pattern).fullmatch(tool_key):
                return True
        except re.error:
            continue
    return False


# MARK: - Session cache

def _check_session_cache(session_id, tool_key):
    cache_path = f"/tmp/claude-notch-session-{session_id}.json"
    try:
        with open(cache_path) as f:
            data = json.load(f)
        return tool_key in data.get("allowed_keys", [])
    except (FileNotFoundError, json.JSONDecodeError, PermissionError):
        return False


# MARK: - Response helpers

def _output_allow(request_id=""):
    response = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow"
        }
    }
    print(json.dumps(response), flush=True)
    sys.exit(0)


def _output_deny(reason="Permission denied"):
    response = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason
        }
    }
    print(json.dumps(response), flush=True)
    sys.exit(2)


# MARK: - Main

def main():
    # 1. Parse hook stdin
    try:
        hook_input = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # malformed input → allow

    session_id = hook_input.get("session_id", "")
    tool_name  = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})

    # 2. Fast-path checks — no socket needed
    tool_key = _make_tool_key(tool_name, tool_input)
    if _check_session_cache(session_id, tool_key):
        _output_allow()
        return
    if _is_allowed_by_settings(tool_name, tool_input):
        _output_allow()
        return

    # 3. Connect to notch app
    request_id = str(uuid.uuid4())
    msg = {
        "message_type": "permission_request",
        "request_id":   request_id,
        "session_id":   session_id,
        "pid":          os.getppid(),
        "tool_name":    tool_name,
        "tool_input":   tool_input,
        "timestamp":    time.time()
    }

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.settimeout(CONNECT_TIMEOUT)
        sock.connect(SOCKET_PATH)
    except (FileNotFoundError, ConnectionRefusedError, OSError):
        # App not running → allow (don't block Claude Code)
        sock.close()
        _output_allow()
        return

    try:
        sock.settimeout(RESPONSE_TIMEOUT)
        _write_framed(sock, msg)
        response = _read_framed(sock)
    except socket.timeout:
        # User didn't respond in time → allow
        sock.close()
        _output_allow()
        return
    except Exception:
        sock.close()
        _output_allow()
        return
    finally:
        sock.close()

    decision = response.get("decision", "allow")
    if decision == "allow":
        _output_allow()
    else:
        _output_deny(response.get("reason", "Permission denied by user"))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Safety net: never hang Claude Code
        _output_allow()
