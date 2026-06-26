import json, sys, os, re

data = json.load(sys.stdin)
cmd = data.get('tool_input', {}).get('command', '')

# A content-search tool is being invoked (covers `git grep` too).
uses_search = re.search(r'\b(grep|egrep|fgrep|rg|ripgrep|ag)\b', cmd) is not None

# gosymdb output never needs grep; let those commands through.
if uses_search and 'gosymdb' not in cmd:
    targets_go = re.search(r'\.go\b', cmd) is not None or '*.go' in cmd
    decl = re.search(r'\b(func|type|interface|struct)\b', cmd) is not None
    in_go_project = os.path.exists('go.mod')

    # Block when grepping .go files directly, or searching for a Go
    # declaration keyword while inside a Go module. The go.mod gate keeps
    # this from firing on `grep type styles.css` in non-Go projects.
    if targets_go or (in_go_project and decl):
        print(json.dumps({
            'hookSpecificOutput': {
                'hookEventName': 'PreToolUse',
                'permissionDecision': 'deny',
                'permissionDecisionReason': (
                    'Do not use grep/rg/find to locate Go symbols. '
                    'Use the gosymdb skills instead (always with --auto-reindex):\n'
                    '  - gosymdb:sym    — find where a symbol is defined\n'
                    '  - gosymdb:trace  — definition + callers + callees\n'
                    '  - gosymdb:impact — blast radius before a refactor/deletion\n'
                    'See CLAUDE.md. If this is a plain text/comment/string search '
                    '(not a symbol lookup), narrow the pattern so it does not look '
                    'like a Go declaration.'
                )
            }
        }))
