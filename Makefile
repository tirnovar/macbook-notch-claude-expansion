.PHONY: build app run clean test-hook

build:
	swift build -c release

app: build
	bash Scripts/build-app.sh

run: app
	open .build/ClaudeNotchExpansion.app

# Run in foreground (useful for seeing logs)
run-fg: app
	.build/ClaudeNotchExpansion.app/Contents/MacOS/ClaudeNotchExpansion

clean:
	swift package clean
	rm -rf .build/ClaudeNotchExpansion.app

# Simulate a permission request (app must be running)
test-hook:
	echo '{"hook_event_name":"PreToolUse","session_id":"test-session-123","tool_name":"Bash","tool_input":{"command":"git push origin main"},"transcript_path":""}' \
		| python3 Sources/ClaudeNotchExpansion/Resources/claude-notch-hook.py

# Simulate a fake session file
test-session:
	python3 -c "\
import json, os, time; \
data = {'pid': os.getpid(), 'sessionId': 'fake-session-001', 'cwd': os.getcwd(), \
        'startedAt': time.time()*1000, 'version': '2.0.0', 'entrypoint': 'claude'}; \
f = open(os.path.expanduser('~/.claude/sessions/fake-session.json'), 'w'); \
json.dump(data, f); f.close(); \
print('Created fake session. Press Ctrl+C to remove.'); \
import signal; signal.pause() \
" ; \
rm -f ~/.claude/sessions/fake-session.json; \
echo "Removed fake session."
