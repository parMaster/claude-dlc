import json, sys

data = json.load(sys.stdin)
cmd = data.get('tool_input', {}).get('command', '')

if 'gosymdb' in cmd and any(p in cmd for p in ['| python', '|python', '| jq', '|jq']):
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': (
                'Do not pipe gosymdb output to python/jq. '
                'gosymdb returns structured JSON - read it directly. '
                'Use a different gosymdb subcommand that already answers the question.'
            )
        }
    }))
