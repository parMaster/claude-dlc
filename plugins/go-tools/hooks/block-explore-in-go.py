import json, sys, os, re

data = json.load(sys.stdin)
ti = data.get('tool_input', {})

# Only relevant for the Explore agent inside a Go module.
if ti.get('subagent_type') == 'Explore' and os.path.exists('go.mod'):
    text = '{} {}'.format(ti.get('description', ''), ti.get('prompt', '')).lower()

    # Signals that the exploration is hunting for Go symbols — the case
    # gosymdb handles. Word matches keep "interface" from firing on
    # unrelated prose while still catching the declaration keywords.
    symbol_intent = re.search(
        r'\b(func|funcs|type|types|interface|interfaces|struct|structs|'
        r'method|methods|receiver|symbol|symbols|caller|callers|callee|'
        r'callees|implementation|implementations|implements|signature|'
        r'definition|defined|declared)\b',
        text,
    ) is not None or '.go' in text

    if symbol_intent:
        print(json.dumps({
            'hookSpecificOutput': {
                'hookEventName': 'PreToolUse',
                'permissionDecision': 'deny',
                'permissionDecisionReason': (
                    'Go symbol lookup detected: use the gosymdb skills '
                    '(gosymdb:sym / gosymdb:trace / gosymdb:impact --auto-reindex) '
                    'instead of the Explore agent. See CLAUDE.md. '
                    '(General, non-symbol exploration of this repo is fine — '
                    'reword without Go-symbol terms.)'
                )
            }
        }))
