import json, sys, os

data = json.load(sys.stdin)
if data.get('tool_input', {}).get('subagent_type') == 'Explore' and os.path.exists('go.mod'):
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': (
                'Go project detected: use gosymdb skills '
                '(gosymdb:sym / gosymdb:trace / gosymdb:impact --auto-reindex) '
                'instead of the Explore agent for Go symbol lookups. See CLAUDE.md.'
            )
        }
    }))
